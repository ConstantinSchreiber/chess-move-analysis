// In-process replacement for Stockfish's main.cpp: runs the UCI loop on its own thread and swaps
// std::cin/std::cout for in-memory buffers so the host app talks to it without pipes or fds.

#include "sfkit.h"

#include <condition_variable>
#include <cstddef>
#include <deque>
#include <iostream>
#include <memory>
#include <mutex>
#include <pthread.h>
#include <streambuf>
#ifdef __APPLE__
    #include <pthread/qos.h>
#endif
#include <string>

#include "attacks.h"
#include "evaluate.h"
#include "misc.h"
#include "position.h"
#include "tune.h"
#include "uci.h"

namespace {

// Blocking line queue read by the UCI loop's std::getline(std::cin, ...).
class InputBuffer final: public std::streambuf {
   public:
    void push(std::string line) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            lines_.push_back(std::move(line));
        }
        ready_.notify_one();
    }

   protected:
    int_type underflow() override {
        if (gptr() < egptr())
            return traits_type::to_int_type(*gptr());

        std::unique_lock<std::mutex> lock(mutex_);
        ready_.wait(lock, [this] { return !lines_.empty(); });
        current_ = std::move(lines_.front());
        lines_.pop_front();
        current_.push_back('\n');
        setg(current_.data(), current_.data(), current_.data() + current_.size());
        return traits_type::to_int_type(*gptr());
    }

   private:
    std::mutex              mutex_;
    std::condition_variable ready_;
    std::deque<std::string> lines_;
    std::string             current_;
};

// Splits everything written to std::cout into lines and hands each to the callback.
class OutputBuffer final: public std::streambuf {
   public:
    OutputBuffer(sfkit_line_callback callback, void* context) :
        callback_(callback),
        context_(context) {}

   protected:
    int_type overflow(int_type ch) override {
        if (traits_type::eq_int_type(ch, traits_type::eof()))
            return traits_type::not_eof(ch);
        std::lock_guard<std::mutex> lock(mutex_);
        append(traits_type::to_char_type(ch));
        return ch;
    }

    std::streamsize xsputn(const char* s, std::streamsize n) override {
        std::lock_guard<std::mutex> lock(mutex_);
        for (std::streamsize i = 0; i < n; ++i)
            append(s[i]);
        return n;
    }

    int sync() override { return 0; }  // only complete lines are delivered

   private:
    void append(char c) {
        if (c != '\n')
        {
            line_.push_back(c);
            return;
        }
        if (!line_.empty() && line_.back() == '\r')
            line_.pop_back();
        if (callback_)
            callback_(line_.c_str(), context_);
        line_.clear();
    }

    std::mutex          mutex_;
    std::string         line_;
    sfkit_line_callback callback_;
    void*               context_;
};

// Process-lifetime objects (intentionally leaked: the engine thread never exits).
InputBuffer& input() {
    static auto* buffer = new InputBuffer();
    return *buffer;
}

std::mutex  startMutex;
bool        started = false;
std::string argv0Storage;

void* engine_main(void*) {
    using namespace Stockfish;

    Attacks::init();
    Position::init();

    char* argv[] = {const_cast<char*>(argv0Storage.c_str()), nullptr};
    auto  uci    = std::make_unique<UCIEngine>(CommandLine(1, argv));

    Tune::init(uci->engine_options());

    uci->loop();  // returns only on "quit"
    return nullptr;
}

}  // namespace

extern "C" {

const char* sfkit_default_net_name(void) { return EvalFileDefaultName; }

int sfkit_start(const char* argv0, sfkit_line_callback callback, void* context) {
    std::lock_guard<std::mutex> lock(startMutex);
    if (started)
        return 0;

    argv0Storage = argv0 ? argv0 : "stockfish";
    std::cout.rdbuf(new OutputBuffer(callback, context));
    std::cin.rdbuf(&input());

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 8 * 1024 * 1024);
#ifdef __APPLE__
    // Search threads are spawned from this thread and inherit its QoS; user-initiated keeps them
    // eligible for performance cores instead of being parked on efficiency cores.
    pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INITIATED, 0);
#endif
    pthread_t thread;
    const int err = pthread_create(&thread, &attr, engine_main, nullptr);
    pthread_attr_destroy(&attr);
    if (err != 0)
        return -1;

    pthread_detach(thread);
    started = true;
    return 1;
}

void sfkit_send(const char* command) {
    if (!command)
        return;
    std::string text(command);
    std::size_t start = 0;
    while (start <= text.size())
    {
        std::size_t end = text.find('\n', start);
        if (end == std::string::npos)
            end = text.size();
        std::string line = text.substr(start, end - start);
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        if (!line.empty())
            input().push(std::move(line));
        start = end + 1;
    }
}

}  // extern "C"

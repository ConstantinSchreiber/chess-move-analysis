"""Network definitions. Both take RGB in [0, 1] and normalise internally (Core ML scale = 1/255)."""
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision

MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)


class Normalize(nn.Module):
    def __init__(self):
        super().__init__()
        self.register_buffer("mean", torch.tensor(MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(STD).view(1, 3, 1, 1))

    def forward(self, x):
        return (x - self.mean) / self.std


def conv_bn_relu(cin, cout, k=3, s=1):
    return nn.Sequential(nn.Conv2d(cin, cout, k, s, k // 2, bias=False), nn.BatchNorm2d(cout), nn.ReLU(inplace=True))


class BoardDetector(nn.Module):
    """ResNet-18 (to layer3) + light stride-32 block, FPN decoder -> 4 corner heatmaps at stride 4.

    (MobileNetV3 was tried first: depthwise convs train ~3x slower on MPS.)
    """

    def __init__(self, pretrained=True, width=96):
        super().__init__()
        weights = torchvision.models.ResNet18_Weights.IMAGENET1K_V1 if pretrained else None
        r = torchvision.models.resnet18(weights=weights)
        self.norm = Normalize()
        self.stem = nn.Sequential(r.conv1, r.bn1, r.relu, r.maxpool)
        self.layer1, self.layer2, self.layer3 = r.layer1, r.layer2, r.layer3
        self.layer4 = nn.Sequential(conv_bn_relu(256, 256, 3, 2), conv_bn_relu(256, 256), conv_bn_relu(256, 256))
        self.lateral = nn.ModuleList([nn.Conv2d(c, width, 1) for c in (64, 128, 256, 256)])
        self.smooth = nn.ModuleList([conv_bn_relu(width, width) for _ in range(3)])
        self.head = nn.Sequential(conv_bn_relu(width, 64), nn.Conv2d(64, 4, 1))
        nn.init.constant_(self.head[-1].bias, -4.0)

    def forward(self, x):
        x = self.norm(x)
        c1 = self.layer1(self.stem(x))
        c2 = self.layer2(c1)
        c3 = self.layer3(c2)
        c4 = self.layer4(c3)
        p = self.lateral[3](c4)
        for lvl, f in ((2, c3), (1, c2), (0, c1)):
            p = F.interpolate(p, scale_factor=2, mode="nearest") + self.lateral[lvl](f)
            p = self.smooth[lvl](p)
        return torch.sigmoid(self.head(p))


class BoardReader(nn.Module):
    """ResNet-18 (to layer3, stride 16) -> 3x3 avg-pool per square -> piece / highlight / flipped heads."""

    def __init__(self, pretrained=True, size=384):
        super().__init__()
        weights = torchvision.models.ResNet18_Weights.IMAGENET1K_V1 if pretrained else None
        r = torchvision.models.resnet18(weights=weights)
        self.norm = Normalize()
        self.stem = nn.Sequential(r.conv1, r.bn1, r.relu, r.maxpool)
        self.layer1, self.layer2, self.layer3 = r.layer1, r.layer2, r.layer3
        self.neck = nn.Sequential(conv_bn_relu(256, 256), conv_bn_relu(256, 256))
        cell = size // 16 // 8  # feature cells per square (3 for 384)
        self.pool = nn.AvgPool2d(cell, cell)
        self.piece_head = nn.Sequential(nn.Conv2d(256, 128, 1), nn.ReLU(inplace=True), nn.Conv2d(128, 13, 1))
        self.hl_head = nn.Sequential(nn.Conv2d(256, 64, 1), nn.ReLU(inplace=True), nn.Conv2d(64, 1, 1))
        self.flip_reduce = nn.Sequential(nn.Conv2d(256 + 13, 24, 1), nn.ReLU(inplace=True))
        self.flip_fc = nn.Sequential(nn.Linear(24 * 64, 256), nn.ReLU(inplace=True), nn.Linear(256, 1))

    def forward_logits(self, x):
        x = self.norm(x)
        x = self.layer3(self.layer2(self.layer1(self.stem(x))))
        x = self.neck(x)
        g = self.pool(x)  # [B,256,8,8]
        piece = self.piece_head(g)  # [B,13,8,8]
        hl = self.hl_head(g)[:, 0]  # [B,8,8]
        f = self.flip_reduce(torch.cat([g, torch.softmax(piece, 1)], 1))
        flip = self.flip_fc(f.flatten(1))[:, 0]  # [B]
        return piece, hl, flip

    def forward(self, x):
        piece, hl, flip = self.forward_logits(x)
        return (torch.softmax(piece, 1).permute(0, 2, 3, 1), torch.sigmoid(hl), torch.sigmoid(flip))


class DetectorExport(nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, x):
        return self.m(x)


class ReaderExport(nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, x):
        return self.m(x)

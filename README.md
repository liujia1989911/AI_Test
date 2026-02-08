# AI_Test
AICoding

## macOS GPU 渲染测试 (Metal)

这个示例使用 Metal 渲染大量实例化三角形来压测 GPU，并实时输出 FPS。

### 构建

```bash
xcrun -sdk macosx metal -c Shaders.metal -o Shaders.air
xcrun -sdk macosx metallib Shaders.air -o default.metallib
clang++ -std=c++17 -fobjc-arc main.mm -framework Cocoa -framework Metal -framework MetalKit -o gpu_test
```

### 运行

```bash
./gpu_test --instances 20000
```

- `--instances` 控制实例数量（默认 20000）。
- 窗口会显示实例化三角形的动画，终端会输出 FPS 作为 GPU 渲染能力参考。

# AIO Setup: AI Model Workflow for NIO 12L
# Uses existing GitHub repos and MediaTek tools — NO custom code

## Tools Available (all from existing sources)

| Tool | Source | Purpose |
|------|--------|---------|
| NeuroPilot Neuron SDK | MediaTek Developer Portal | TFLite→DLA conversion, NPU inference |
| ONNX Runtime | github: microsoft/onnxruntime | ONNX model inference (CPU) |
| PyTorch | github: pytorch/pytorch | Model development/training (CPU) |
| ncc-tflite | NeuroPilot SDK | Compile TFLite models to DLA format |
| neuronrt | NeuroPilot SDK | Run DLA models on NPU |
| vpu5_test | mediatek-neuron-utils | NPU hardware verification |

## Workflow

### 1. Verify NPU
```bash
vpu5_test -a ks -l 10
# Expected output: PASS
```

### 2. Convert Model for NPU (TFLite → DLA)
```bash
# Download NeuroPilot SDK from https://neuropilot-developer.mediatek.com
# Extract and set up
export LD_LIBRARY_PATH=/path/to/neuron_sdk/host/lib

# Convert TFLite → DLA for Genio 1200 (mdla3.0)
ncc-tflite --arch=mdla3.0 model.tflite -o model.dla

# With INT8 quantization
ncc-tflite --arch=mdla3.0 --quantize model.tflite -o model_quant.dla
```

### 3. Run Inference on NPU
```bash
# Run DLA model on hardware
neuronrt -m hw -a model.dla -i input.bin -c 10
```

### 4. Run ONNX Models on CPU
```bash
pip3 install onnxruntime
python3 -c "
import onnxruntime as ort
sess = ort.InferenceSession('model.onnx')
# ... run inference
"
```

### 5. Check NPU Performance
```bash
vpu5_test -a ks -l 10  # Benchmark
# Compare with CPU:
python3 -c "import onnxruntime as ort; ..."
```

## Model Repository

Place converted models in:
```bash
mkdir -p /usr/local/share/npu-models
cp model.dla /usr/local/share/npu-models/
```

## References

- [NeuroPilot Developer Portal](https://neuropilot-developer.mediatek.com/resources/public/latest/en/docs/readme)
- [Neuron SDK Docs (GitLab)](https://mediatek.gitlab.io/aiot/doc/aiot-dev-guide/release/v25.0/sw/yocto/ml-guide/ml-neuron-sdk.html)
- [Genio AI Hub](https://genio.mediatek.com/doc/iot-aihub/ai_hub/ai-workflow/neuron-sdk.html)

# ComfyUI API Integration Guide

This guide explains how to use ComfyUI's REST API for integration into agent workflows, MCP services, and automation pipelines using standard HTTP tools like `curl`.

## Table of Contents

1. [Overview](#overview)
2. [API Endpoints](#api-endpoints)
3. [Basic Workflow](#basic-workflow)
4. [Complete Example: Erase Rectangle Region](#complete-example-erase-rectangle-region)
5. [Advanced Usage](#advanced-usage)
6. [Tips for MCP Services](#tips-for-mcp-services)

## Overview

ComfyUI exposes a REST API that allows you to:
- Upload images to the input directory
- Submit workflow prompts for execution
- Monitor execution status
- Retrieve generated outputs

The API runs on `http://127.0.0.1:8188` by default.

## API Endpoints

### Core Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/upload/image` | Upload an image to the input directory |
| POST | `/prompt` | Queue a workflow for execution |
| GET | `/prompt` | Get queue status |
| GET | `/queue` | Get current queue state |
| GET | `/history` | Get execution history |
| GET | `/history/{prompt_id}` | Get specific execution result |
| GET | `/view` | View/download an image |
| GET | `/object_info` | Get all available node types |
| GET | `/object_info/{node_class}` | Get info about a specific node |
| POST | `/interrupt` | Interrupt current execution |
| POST | `/queue` | Manage queue (clear/delete) |

## Basic Workflow

### Step 1: Upload an Image

```bash
# Upload an image to ComfyUI's input directory
curl -X POST "http://127.0.0.1:8188/upload/image" \
  -F "image=@/path/to/your/image.png" \
  -F "type=input" \
  -F "overwrite=true"
```

Response:
```json
{
  "name": "image.png",
  "subfolder": "",
  "type": "input"
}
```

### Step 2: Create and Submit a Workflow Prompt

The prompt format uses a JSON object where each key is a unique node ID, and each value contains:
- `class_type`: The node type (e.g., "LoadImage", "SaveImage")
- `inputs`: The node's input parameters

```bash
# Submit a workflow prompt
curl -X POST "http://127.0.0.1:8188/prompt" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": {
      "1": {
        "class_type": "LoadImage",
        "inputs": {
          "image": "image.png"
        }
      },
      "2": {
        "class_type": "SaveImage",
        "inputs": {
          "filename_prefix": "output",
          "images": ["1", 0]
        }
      }
    }
  }'
```

Response:
```json
{
  "prompt_id": "abc123-def456-...",
  "number": 1,
  "node_errors": {}
}
```

**Note**: Node connections use arrays `[node_id, output_index]` where:
- `node_id` is the string ID of the source node
- `output_index` is the index of the output (usually 0)

### Step 3: Poll for Completion

```bash
# Check execution history for the prompt
curl "http://127.0.0.1:8188/history/{prompt_id}"
```

Response when complete:
```json
{
  "abc123-def456-...": {
    "prompt": [...],
    "outputs": {
      "2": {
        "images": [
          {
            "filename": "output_00001_.png",
            "subfolder": "",
            "type": "output"
          }
        ]
      }
    },
    "status": {
      "status_str": "success",
      "completed": true,
      "messages": [...]
    }
  }
}
```

### Step 4: Download the Result

```bash
# Download the output image
curl "http://127.0.0.1:8188/view?filename=output_00001_.png&type=output" \
  --output result.png
```

## Complete Example: Erase Rectangle Region

This example demonstrates how to erase (fill with solid color) a rectangular region in an image using ComfyUI's API.

### Workflow Overview

1. **LoadImage** - Load the source image
2. **SolidMask** - Create a mask for the rectangle region
3. **MaskComposite** - Position the mask on a full-size empty mask
4. **ImageCompositeMasked** - Composite a solid color over the masked region
5. **SaveImage** - Save the result

### Shell Script Implementation

```bash
#!/bin/bash

# Configuration
COMFY_URL="http://127.0.0.1:8188"
INPUT_IMAGE="$1"           # Path to input image
OUTPUT_PREFIX="erased"     # Output filename prefix
RECT_X="${2:-100}"         # Rectangle X position
RECT_Y="${3:-100}"         # Rectangle Y position
RECT_WIDTH="${4:-200}"     # Rectangle width
RECT_HEIGHT="${5:-200}"    # Rectangle height
FILL_COLOR="${6:-16777215}"  # Fill color as integer (0=black, 16777215=white, i.e., 0xFFFFFF)

# Step 1: Upload the image
echo "Uploading image..."
UPLOAD_RESPONSE=$(curl -s -X POST "${COMFY_URL}/upload/image" \
  -F "image=@${INPUT_IMAGE}" \
  -F "type=input" \
  -F "overwrite=true")

# Note: The grep/cut approach below is a basic fallback. For production use, install jq.
# With jq: IMAGE_NAME=$(echo "$UPLOAD_RESPONSE" | jq -r '.name')
IMAGE_NAME=$(echo "$UPLOAD_RESPONSE" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
echo "Uploaded as: $IMAGE_NAME"

# Step 2: Get image dimensions (we need these for the workflow)
# For simplicity, we'll use the mask composite to handle positioning

# Step 3: Submit the workflow
echo "Submitting workflow..."
PROMPT_RESPONSE=$(curl -s -X POST "${COMFY_URL}/prompt" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": {
      "load_image": {
        "class_type": "LoadImage",
        "inputs": {
          "image": "'"${IMAGE_NAME}"'"
        }
      },
      "solid_mask": {
        "class_type": "SolidMask",
        "inputs": {
          "value": 1.0,
          "width": '"${RECT_WIDTH}"',
          "height": '"${RECT_HEIGHT}"'
        }
      },
      "empty_mask": {
        "class_type": "SolidMask",
        "inputs": {
          "value": 0.0,
          "width": 4096,
          "height": 4096
        }
      },
      "mask_composite": {
        "class_type": "MaskComposite",
        "inputs": {
          "destination": ["empty_mask", 0],
          "source": ["solid_mask", 0],
          "x": '"${RECT_X}"',
          "y": '"${RECT_Y}"',
          "operation": "add"
        }
      },
      "solid_image": {
        "class_type": "EmptyImage",
        "inputs": {
          "width": 4096,
          "height": 4096,
          "batch_size": 1,
          "color": '"${FILL_COLOR}"'
        }
      },
      "composite": {
        "class_type": "ImageCompositeMasked",
        "inputs": {
          "destination": ["load_image", 0],
          "source": ["solid_image", 0],
          "x": 0,
          "y": 0,
          "resize_source": true,
          "mask": ["mask_composite", 0]
        }
      },
      "save_image": {
        "class_type": "SaveImage",
        "inputs": {
          "filename_prefix": "'"${OUTPUT_PREFIX}"'",
          "images": ["composite", 0]
        }
      }
    }
  }')

PROMPT_ID=$(echo "$PROMPT_RESPONSE" | grep -o '"prompt_id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
echo "Prompt ID: $PROMPT_ID"

# Step 4: Poll for completion
echo "Waiting for completion..."
while true; do
  HISTORY=$(curl -s "${COMFY_URL}/history/${PROMPT_ID}")
  
  # Check if the prompt_id exists in history (indicates completion)
  if echo "$HISTORY" | grep -q '"status_str"'; then
    STATUS=$(echo "$HISTORY" | grep -o '"status_str"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    if [ "$STATUS" = "success" ]; then
      echo "Execution completed successfully!"
      break
    elif [ "$STATUS" = "error" ]; then
      echo "Execution failed!"
      echo "$HISTORY"
      exit 1
    fi
  fi
  
  sleep 1
done

# Step 5: Get the output filename and download
OUTPUT_FILENAME=$(echo "$HISTORY" | grep -o '"filename"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
echo "Downloading: $OUTPUT_FILENAME"

curl -s "${COMFY_URL}/view?filename=${OUTPUT_FILENAME}&type=output" --output "${OUTPUT_PREFIX}_result.png"
echo "Saved to: ${OUTPUT_PREFIX}_result.png"
```

### Usage

```bash
# Make the script executable
chmod +x erase_rectangle.sh

# Run with default parameters (100,100 position, 200x200 size)
./erase_rectangle.sh input.png

# Run with custom rectangle
./erase_rectangle.sh input.png 50 75 300 150 1.0
```

### Alternative: Using jq for JSON Parsing

For more robust JSON handling, use `jq`:

```bash
#!/bin/bash

COMFY_URL="http://127.0.0.1:8188"

# Upload image
UPLOAD_RESPONSE=$(curl -s -X POST "${COMFY_URL}/upload/image" \
  -F "image=@$1" \
  -F "type=input")
IMAGE_NAME=$(echo "$UPLOAD_RESPONSE" | jq -r '.name')

# Submit prompt and get ID
PROMPT_RESPONSE=$(curl -s -X POST "${COMFY_URL}/prompt" \
  -H "Content-Type: application/json" \
  -d @workflow.json)
PROMPT_ID=$(echo "$PROMPT_RESPONSE" | jq -r '.prompt_id')

# Poll for completion
while true; do
  HISTORY=$(curl -s "${COMFY_URL}/history/${PROMPT_ID}")
  COMPLETED=$(echo "$HISTORY" | jq -r --arg id "$PROMPT_ID" '.[$id].status.completed // false')
  if [ "$COMPLETED" = "true" ]; then
    break
  fi
  sleep 1
done

# Download result
OUTPUT_FILE=$(echo "$HISTORY" | jq -r --arg id "$PROMPT_ID" '.[$id].outputs | to_entries[0].value.images[0].filename')
curl -s "${COMFY_URL}/view?filename=${OUTPUT_FILE}&type=output" -o result.png
```

## Advanced Usage

### Using WebSocket for Real-time Updates

For production use, consider using WebSocket to receive real-time execution updates instead of polling:

```bash
# Connect to WebSocket (requires wscat or similar)
wscat -c "ws://127.0.0.1:8188/ws?clientId=my-client-id"
```

See `websockets_api_example.py` in this directory for a Python implementation.

### Get Available Nodes

```bash
# List all available node types
curl "http://127.0.0.1:8188/object_info" | jq 'keys'

# Get details about a specific node
curl "http://127.0.0.1:8188/object_info/SolidMask" | jq
```

### Managing the Queue

```bash
# Clear the entire queue
curl -X POST "http://127.0.0.1:8188/queue" \
  -H "Content-Type: application/json" \
  -d '{"clear": true}'

# Delete specific prompts from queue
curl -X POST "http://127.0.0.1:8188/queue" \
  -H "Content-Type: application/json" \
  -d '{"delete": ["prompt_id_1", "prompt_id_2"]}'

# Interrupt current execution
curl -X POST "http://127.0.0.1:8188/interrupt"
```

### Uploading Masks

```bash
# Upload a mask image with reference to original
curl -X POST "http://127.0.0.1:8188/upload/mask" \
  -F "image=@mask.png" \
  -F 'original_ref={"filename": "original.png", "type": "input"}'
```

## Tips for MCP Services

When integrating ComfyUI into an MCP (Model Context Protocol) service:

### 1. Error Handling

Always check the response for errors:

```bash
RESPONSE=$(curl -s -X POST "${COMFY_URL}/prompt" -H "Content-Type: application/json" -d "$WORKFLOW")
ERROR=$(echo "$RESPONSE" | jq -r '.error // empty')
if [ -n "$ERROR" ]; then
  echo "Error: $ERROR"
  exit 1
fi
```

### 2. Timeout Handling

Set appropriate timeouts for long-running operations:

```bash
# Use curl's timeout options
curl --max-time 300 --connect-timeout 10 "${COMFY_URL}/prompt" ...
```

### 3. Unique Prompt IDs

Generate unique prompt IDs to track multiple concurrent requests:

```bash
PROMPT_ID=$(uuidgen)
curl -X POST "${COMFY_URL}/prompt" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": {...},
    "prompt_id": "'"${PROMPT_ID}"'"
  }'
```

### 4. Health Check

Check if ComfyUI is running before making requests:

```bash
if ! curl -s --max-time 5 "${COMFY_URL}/system_stats" > /dev/null 2>&1; then
  echo "ComfyUI is not available"
  exit 1
fi
```

### 5. Export Workflows from UI

You can design workflows in the ComfyUI web interface and export them for API use:
1. Open ComfyUI web interface
2. Create your workflow visually
3. Go to **Menu → File → Export (API)**
4. This generates the JSON format needed for the `/prompt` endpoint

### 6. Complete MCP Tool Example

```bash
#!/bin/bash
# mcp_erase_rectangle.sh - MCP tool for erasing rectangle regions

set -e

# Parse MCP tool arguments
INPUT_FILE="$1"
X="$2"
Y="$3"
WIDTH="$4"
HEIGHT="$5"

COMFY_URL="${COMFY_URL:-http://127.0.0.1:8188}"
TIMEOUT="${TIMEOUT:-300}"

# Validate inputs
if [ -z "$INPUT_FILE" ] || [ -z "$X" ] || [ -z "$Y" ] || [ -z "$WIDTH" ] || [ -z "$HEIGHT" ]; then
  echo '{"error": "Missing required parameters: INPUT_FILE X Y WIDTH HEIGHT"}'
  exit 1
fi

# Health check
if ! curl -s --max-time 5 "${COMFY_URL}/system_stats" > /dev/null 2>&1; then
  echo '{"error": "ComfyUI server not available"}'
  exit 1
fi

# Upload
UPLOAD_RESP=$(curl -s -X POST "${COMFY_URL}/upload/image" \
  -F "image=@${INPUT_FILE}" -F "type=input" -F "overwrite=true")
IMAGE_NAME=$(echo "$UPLOAD_RESP" | jq -r '.name // empty')

if [ -z "$IMAGE_NAME" ]; then
  echo '{"error": "Failed to upload image"}'
  exit 1
fi

# Generate unique prompt ID
PROMPT_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen || echo "prompt-$(date +%s)")

# Submit workflow
WORKFLOW=$(cat <<EOF
{
  "prompt": {
    "1": {"class_type": "LoadImage", "inputs": {"image": "${IMAGE_NAME}"}},
    "2": {"class_type": "SolidMask", "inputs": {"value": 1.0, "width": ${WIDTH}, "height": ${HEIGHT}}},
    "3": {"class_type": "SolidMask", "inputs": {"value": 0.0, "width": 8192, "height": 8192}},
    "4": {"class_type": "MaskComposite", "inputs": {"destination": ["3", 0], "source": ["2", 0], "x": ${X}, "y": ${Y}, "operation": "add"}},
    "5": {"class_type": "EmptyImage", "inputs": {"width": 8192, "height": 8192, "batch_size": 1, "color": 16777215}},
    "6": {"class_type": "ImageCompositeMasked", "inputs": {"destination": ["1", 0], "source": ["5", 0], "x": 0, "y": 0, "resize_source": true, "mask": ["4", 0]}},
    "7": {"class_type": "SaveImage", "inputs": {"filename_prefix": "mcp_erased", "images": ["6", 0]}}
  },
  "prompt_id": "${PROMPT_ID}"
}
EOF
)

PROMPT_RESP=$(curl -s --max-time 30 -X POST "${COMFY_URL}/prompt" \
  -H "Content-Type: application/json" -d "$WORKFLOW")

if echo "$PROMPT_RESP" | jq -e '.error' > /dev/null 2>&1; then
  echo "$PROMPT_RESP"
  exit 1
fi

# Poll for completion
START_TIME=$(date +%s)
while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  
  if [ $ELAPSED -gt $TIMEOUT ]; then
    echo '{"error": "Timeout waiting for completion"}'
    exit 1
  fi
  
  HISTORY=$(curl -s "${COMFY_URL}/history/${PROMPT_ID}")
  STATUS=$(echo "$HISTORY" | jq -r --arg id "$PROMPT_ID" '.[$id].status.status_str // empty')
  
  if [ "$STATUS" = "success" ]; then
    OUTPUT_FILE=$(echo "$HISTORY" | jq -r --arg id "$PROMPT_ID" '.[$id].outputs["7"].images[0].filename')
    echo "{\"status\": \"success\", \"output_file\": \"${OUTPUT_FILE}\", \"download_url\": \"${COMFY_URL}/view?filename=${OUTPUT_FILE}&type=output\"}"
    exit 0
  elif [ "$STATUS" = "error" ]; then
    echo '{"error": "Workflow execution failed"}'
    exit 1
  fi
  
  sleep 1
done
```

## Reference: Common Node Types

| Node Class | Purpose | Key Inputs |
|------------|---------|------------|
| `LoadImage` | Load an image from input directory | `image` (filename) |
| `SaveImage` | Save images to output directory | `images`, `filename_prefix` |
| `SolidMask` | Create a solid color mask | `value`, `width`, `height` |
| `MaskComposite` | Combine/position masks | `destination`, `source`, `x`, `y`, `operation` |
| `ImageCompositeMasked` | Composite images using mask | `destination`, `source`, `mask`, `x`, `y` |
| `InvertMask` | Invert a mask | `mask` |
| `EmptyImage` | Create a solid color image | `width`, `height`, `color`, `batch_size` |
| `ImageToMask` | Convert image channel to mask | `image`, `channel` |
| `CropMask` | Crop a mask to region | `mask`, `x`, `y`, `width`, `height` |

For a complete list of nodes and their parameters, query the `/object_info` endpoint.

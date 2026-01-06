#!/bin/bash
#
# erase_rectangle_api.sh - Erase a rectangular region in an image using ComfyUI API
#
# Usage: ./erase_rectangle_api.sh <image_path> [x] [y] [width] [height] [fill_color]
#
# Arguments:
#   image_path  - Path to the input image (required)
#   x           - X position of rectangle (default: 100)
#   y           - Y position of rectangle (default: 100)
#   width       - Width of rectangle (default: 200)
#   height      - Height of rectangle (default: 200)
#   fill_color  - Fill color as hex integer, e.g., 16777215 for white (default: white)
#
# Environment:
#   COMFY_URL   - ComfyUI server URL (default: http://127.0.0.1:8188)
#   TIMEOUT     - Max wait time in seconds (default: 300)
#
# Example:
#   ./erase_rectangle_api.sh photo.png 50 75 300 150
#   COMFY_URL=http://192.168.1.100:8188 ./erase_rectangle_api.sh photo.png
#

set -e

# Configuration
COMFY_URL="${COMFY_URL:-http://127.0.0.1:8188}"
TIMEOUT="${TIMEOUT:-300}"

# Maximum canvas size for the solid fill/mask images
# This should be larger than any input image dimensions
MAX_CANVAS_SIZE=8192

# Arguments
INPUT_IMAGE="$1"
RECT_X="${2:-100}"
RECT_Y="${3:-100}"
RECT_WIDTH="${4:-200}"
RECT_HEIGHT="${5:-200}"
FILL_COLOR="${6:-16777215}"  # Default: white (0xFFFFFF = 16777215)

# Validate input
if [ -z "$INPUT_IMAGE" ]; then
    echo "Usage: $0 <image_path> [x] [y] [width] [height] [fill_color]"
    echo ""
    echo "Example: $0 photo.png 100 100 200 200"
    exit 1
fi

if [ ! -f "$INPUT_IMAGE" ]; then
    echo "Error: File not found: $INPUT_IMAGE"
    exit 1
fi

# Check if jq is available for JSON parsing (strongly recommended)
USE_JQ=false
if command -v jq &> /dev/null; then
    USE_JQ=true
else
    echo "Warning: jq not found. Using basic string parsing (less reliable)."
    echo "For production use, install jq: apt-get install jq / brew install jq"
fi

# Function to extract a string value from JSON by key name
# Note: Only works for simple top-level string values when jq is not available
json_extract_string() {
    local json="$1"
    local key="$2"
    if [ "$USE_JQ" = true ]; then
        echo "$json" | jq -r ".$key // empty"
    else
        # Regex breakdown: Match "key" : "value" pattern
        # - \"$key\"           - match the key name in quotes
        # - [[:space:]]*:[[:space:]]* - match colon with optional whitespace
        # - \"[^\"]*\"         - match the value in quotes ([^\"]*) matches any chars except quote)
        # Then extract just the value part with sed
        echo "$json" | grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/'
    fi
}

echo "=== ComfyUI Rectangle Eraser ==="
echo "Server: $COMFY_URL"
echo "Input:  $INPUT_IMAGE"
echo "Rectangle: x=$RECT_X, y=$RECT_Y, w=$RECT_WIDTH, h=$RECT_HEIGHT"
echo ""

# Step 1: Health check
echo "[1/5] Checking server..."
if ! curl -s --max-time 5 "${COMFY_URL}/system_stats" > /dev/null 2>&1; then
    echo "Error: ComfyUI server not available at $COMFY_URL"
    echo "Make sure ComfyUI is running: python main.py"
    exit 1
fi
echo "      Server is running."

# Step 2: Upload image
echo "[2/5] Uploading image..."
UPLOAD_RESPONSE=$(curl -s -X POST "${COMFY_URL}/upload/image" \
    -F "image=@${INPUT_IMAGE}" \
    -F "type=input" \
    -F "overwrite=true")

IMAGE_NAME=$(json_extract_string "$UPLOAD_RESPONSE" "name")

if [ -z "$IMAGE_NAME" ]; then
    echo "Error: Failed to upload image"
    echo "Response: $UPLOAD_RESPONSE"
    exit 1
fi
echo "      Uploaded as: $IMAGE_NAME"

# Step 3: Generate unique prompt ID
PROMPT_ID="erase-$(date +%s)-$$"

# Step 4: Submit workflow
echo "[3/5] Submitting workflow..."

# The workflow:
# 1. Load the image
# 2. Create a rectangle mask (SolidMask)
# 3. Create an empty base mask
# 4. Position the rectangle mask on the base mask (MaskComposite)
# 5. Create a solid fill image
# 6. Composite the fill over the image using the mask
# 7. Save the result

WORKFLOW=$(cat <<EOF
{
    "prompt": {
        "load": {
            "class_type": "LoadImage",
            "inputs": {
                "image": "${IMAGE_NAME}"
            }
        },
        "rect_mask": {
            "class_type": "SolidMask",
            "inputs": {
                "value": 1.0,
                "width": ${RECT_WIDTH},
                "height": ${RECT_HEIGHT}
            }
        },
        "base_mask": {
            "class_type": "SolidMask",
            "inputs": {
                "value": 0.0,
                "width": ${MAX_CANVAS_SIZE},
                "height": ${MAX_CANVAS_SIZE}
            }
        },
        "position_mask": {
            "class_type": "MaskComposite",
            "inputs": {
                "destination": ["base_mask", 0],
                "source": ["rect_mask", 0],
                "x": ${RECT_X},
                "y": ${RECT_Y},
                "operation": "add"
            }
        },
        "fill_image": {
            "class_type": "EmptyImage",
            "inputs": {
                "width": ${MAX_CANVAS_SIZE},
                "height": ${MAX_CANVAS_SIZE},
                "batch_size": 1,
                "color": ${FILL_COLOR}
            }
        },
        "composite": {
            "class_type": "ImageCompositeMasked",
            "inputs": {
                "destination": ["load", 0],
                "source": ["fill_image", 0],
                "x": 0,
                "y": 0,
                "resize_source": true,
                "mask": ["position_mask", 0]
            }
        },
        "save": {
            "class_type": "SaveImage",
            "inputs": {
                "filename_prefix": "erased",
                "images": ["composite", 0]
            }
        }
    },
    "prompt_id": "${PROMPT_ID}"
}
EOF
)

PROMPT_RESPONSE=$(curl -s --max-time 30 -X POST "${COMFY_URL}/prompt" \
    -H "Content-Type: application/json" \
    -d "$WORKFLOW")

# Check for errors
if echo "$PROMPT_RESPONSE" | grep -q '"error"'; then
    echo "Error: Failed to submit workflow"
    echo "Response: $PROMPT_RESPONSE"
    exit 1
fi
echo "      Prompt ID: $PROMPT_ID"

# Step 5: Wait for completion
echo "[4/5] Waiting for completion..."
START_TIME=$(date +%s)
OUTPUT_FILENAME=""

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -gt $TIMEOUT ]; then
        echo "Error: Timeout after ${TIMEOUT}s"
        exit 1
    fi
    
    HISTORY=$(curl -s "${COMFY_URL}/history/${PROMPT_ID}")
    
    # Check status
    if [ "$USE_JQ" = true ]; then
        STATUS=$(echo "$HISTORY" | jq -r --arg id "$PROMPT_ID" '.[$id].status.status_str // empty')
        if [ "$STATUS" = "success" ]; then
            OUTPUT_FILENAME=$(echo "$HISTORY" | jq -r --arg id "$PROMPT_ID" '.[$id].outputs.save.images[0].filename // empty')
            break
        elif [ "$STATUS" = "error" ]; then
            echo "Error: Workflow execution failed"
            echo "$HISTORY" | jq --arg id "$PROMPT_ID" '.[$id].status'
            exit 1
        fi
    else
        if echo "$HISTORY" | grep -q '"status_str"[[:space:]]*:[[:space:]]*"success"'; then
            OUTPUT_FILENAME=$(echo "$HISTORY" | grep -o '"filename"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
            break
        elif echo "$HISTORY" | grep -q '"status_str"[[:space:]]*:[[:space:]]*"error"'; then
            echo "Error: Workflow execution failed"
            exit 1
        fi
    fi
    
    printf "\r      Elapsed: ${ELAPSED}s"
    sleep 1
done

echo ""
echo "      Completed!"

# Step 6: Download result
echo "[5/5] Downloading result..."

if [ -z "$OUTPUT_FILENAME" ]; then
    echo "Error: Could not determine output filename"
    exit 1
fi

# Create output filename based on input
INPUT_BASENAME=$(basename "$INPUT_IMAGE")
INPUT_NAME="${INPUT_BASENAME%.*}"
OUTPUT_PATH="${INPUT_NAME}_erased.png"

curl -s "${COMFY_URL}/view?filename=${OUTPUT_FILENAME}&type=output" --output "$OUTPUT_PATH"

echo "      Saved to: $OUTPUT_PATH"
echo ""
echo "=== Done! ==="
echo "Original: $INPUT_IMAGE"
echo "Result:   $OUTPUT_PATH"

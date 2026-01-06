#!/bin/bash
#
# curl_api_quick_reference.sh - Quick reference for ComfyUI API curl commands
#
# This file contains copy-paste ready curl commands for common operations.
# Replace placeholder values with your actual data.
#

SERVER="http://127.0.0.1:8188"

# ============================================================================
# HEALTH CHECK
# ============================================================================

# Check if server is running
curl -s "$SERVER/system_stats" | head -c 100

# Get queue status
curl -s "$SERVER/prompt"

# ============================================================================
# IMAGE UPLOAD
# ============================================================================

# Upload an image (returns {"name": "filename.png", "subfolder": "", "type": "input"})
curl -X POST "$SERVER/upload/image" \
    -F "image=@your_image.png" \
    -F "type=input"

# Upload with overwrite
curl -X POST "$SERVER/upload/image" \
    -F "image=@your_image.png" \
    -F "type=input" \
    -F "overwrite=true"

# Upload to subfolder
curl -X POST "$SERVER/upload/image" \
    -F "image=@your_image.png" \
    -F "type=input" \
    -F "subfolder=my_folder"

# ============================================================================
# SUBMIT WORKFLOW
# ============================================================================

# Submit a simple workflow (load image -> save image)
curl -X POST "$SERVER/prompt" \
    -H "Content-Type: application/json" \
    -d '{
        "prompt": {
            "1": {
                "class_type": "LoadImage",
                "inputs": {"image": "your_image.png"}
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

# Submit with custom prompt ID
curl -X POST "$SERVER/prompt" \
    -H "Content-Type: application/json" \
    -d '{
        "prompt": {...},
        "prompt_id": "my-custom-id-12345"
    }'

# ============================================================================
# CHECK STATUS & HISTORY
# ============================================================================

# Get execution history (all)
curl -s "$SERVER/history"

# Get history for specific prompt
curl -s "$SERVER/history/YOUR_PROMPT_ID"

# Get current queue state
curl -s "$SERVER/queue"

# ============================================================================
# DOWNLOAD RESULTS
# ============================================================================

# Download output image
curl "$SERVER/view?filename=output_00001_.png&type=output" -o result.png

# Download from temp folder
curl "$SERVER/view?filename=temp_image.png&type=temp" -o temp.png

# Download from input folder
curl "$SERVER/view?filename=input_image.png&type=input" -o input.png

# Download from subfolder
curl "$SERVER/view?filename=image.png&subfolder=my_folder&type=output" -o result.png

# ============================================================================
# QUEUE MANAGEMENT
# ============================================================================

# Clear entire queue
curl -X POST "$SERVER/queue" \
    -H "Content-Type: application/json" \
    -d '{"clear": true}'

# Delete specific prompts from queue
curl -X POST "$SERVER/queue" \
    -H "Content-Type: application/json" \
    -d '{"delete": ["prompt_id_1", "prompt_id_2"]}'

# Interrupt current execution
curl -X POST "$SERVER/interrupt"

# Interrupt specific prompt
curl -X POST "$SERVER/interrupt" \
    -H "Content-Type: application/json" \
    -d '{"prompt_id": "specific-prompt-id"}'

# ============================================================================
# NODE INFORMATION
# ============================================================================

# List all available nodes (requires jq)
curl -s "$SERVER/object_info" | jq -r 'keys[]' | sort

# Alternative: list nodes using grep (less reliable but no dependencies)
# curl -s "$SERVER/object_info" | grep -o '"[^"]*":' | tr -d '":' | sort | uniq

# Get info about specific node
curl -s "$SERVER/object_info/LoadImage"
curl -s "$SERVER/object_info/SaveImage"
curl -s "$SERVER/object_info/SolidMask"
curl -s "$SERVER/object_info/ImageCompositeMasked"

# List all model types
curl -s "$SERVER/models"

# List models in specific folder
curl -s "$SERVER/models/checkpoints"
curl -s "$SERVER/models/loras"

# ============================================================================
# COMPLETE WORKFLOW EXAMPLE: ERASE RECTANGLE
# ============================================================================

# This workflow erases a 200x200 rectangle at position (100,100) with white fill

curl -X POST "$SERVER/prompt" \
    -H "Content-Type: application/json" \
    -d '{
        "prompt": {
            "load": {
                "class_type": "LoadImage",
                "inputs": {"image": "your_image.png"}
            },
            "rect_mask": {
                "class_type": "SolidMask",
                "inputs": {"value": 1.0, "width": 200, "height": 200}
            },
            "base_mask": {
                "class_type": "SolidMask",
                "inputs": {"value": 0.0, "width": 8192, "height": 8192}
            },
            "combined_mask": {
                "class_type": "MaskComposite",
                "inputs": {
                    "destination": ["base_mask", 0],
                    "source": ["rect_mask", 0],
                    "x": 100,
                    "y": 100,
                    "operation": "add"
                }
            },
            "fill": {
                "class_type": "EmptyImage",
                "inputs": {"width": 8192, "height": 8192, "batch_size": 1, "color": 16777215}
            },
            "composite": {
                "class_type": "ImageCompositeMasked",
                "inputs": {
                    "destination": ["load", 0],
                    "source": ["fill", 0],
                    "x": 0, "y": 0,
                    "resize_source": true,
                    "mask": ["combined_mask", 0]
                }
            },
            "save": {
                "class_type": "SaveImage",
                "inputs": {"filename_prefix": "erased", "images": ["composite", 0]}
            }
        }
    }'

# ============================================================================
# WEBSOCKET CONNECTION (requires wscat)
# ============================================================================

# Connect for real-time updates
# wscat -c "ws://127.0.0.1:8188/ws?clientId=my-client"

# ============================================================================
# JOB API (newer endpoints)
# ============================================================================

# List all jobs
curl -s "$SERVER/api/jobs"

# List jobs with filters
curl -s "$SERVER/api/jobs?status=completed&limit=10"

# Get specific job
curl -s "$SERVER/api/jobs/YOUR_PROMPT_ID"

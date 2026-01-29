#!/usr/bin/env python3
"""
Aztec barcode decoder using zxing-cpp library.

This script provides a command-line interface for decoding Aztec barcodes
with detailed error messages and diagnostic output.

Usage:
    python3 aztec_decode.py <image_path> [--verbose] [--raw] [--json]

Requirements:
    pip install zxing-cpp pillow

Example:
    # Activate venv first
    source /tmp/zxing-venv/bin/activate
    pip install pillow  # If not installed

    python3 aztec_decode.py /tmp/azteclib_test.png --verbose
"""

import sys
import argparse
import json
from pathlib import Path

def decode_aztec(image_path: str, verbose: bool = False) -> dict:
    """
    Decode Aztec barcode from image file.

    Returns dict with:
        - success: bool
        - text: str (decoded text, if successful)
        - bytes: list[int] (raw bytes, if successful)
        - format: str (barcode format detected)
        - position: dict (bounding box if detected)
        - error: str (error message if failed)
    """
    result = {
        "success": False,
        "text": None,
        "bytes": None,
        "format": None,
        "position": None,
        "error": None
    }

    try:
        import zxingcpp
    except ImportError:
        result["error"] = "zxing-cpp not installed. Run: pip install zxing-cpp"
        return result

    try:
        from PIL import Image
    except ImportError:
        result["error"] = "Pillow not installed. Run: pip install pillow"
        return result

    # Load image
    try:
        img = Image.open(image_path)
        if verbose:
            print(f"Image loaded: {img.size[0]}x{img.size[1]}, mode={img.mode}", file=sys.stderr)
    except Exception as e:
        result["error"] = f"Failed to load image: {e}"
        return result

    # Convert to RGB if necessary (zxing-cpp works best with RGB)
    if img.mode not in ('RGB', 'L'):
        img = img.convert('RGB')
        if verbose:
            print(f"Converted to RGB", file=sys.stderr)

    if verbose:
        print(f"Scanning for Aztec codes...", file=sys.stderr)

    # Read barcodes (zxing-cpp 2.x API)
    try:
        barcodes = zxingcpp.read_barcodes(img)
    except Exception as e:
        result["error"] = f"zxing-cpp read error: {e}"
        return result

    # Filter for Aztec codes
    barcodes = [b for b in barcodes if b.format == zxingcpp.BarcodeFormat.Aztec]

    if not barcodes:
        result["error"] = "No Aztec barcode detected in image"

        # Try with all formats to see if other barcodes are present
        if verbose:
            reader_options.formats = zxingcpp.BarcodeFormat.LinearCodes | zxingcpp.BarcodeFormat.MatrixCodes
            all_barcodes = zxingcpp.read_barcodes(img, reader_options)
            if all_barcodes:
                found_formats = [str(b.format) for b in all_barcodes]
                print(f"Other barcodes found: {found_formats}", file=sys.stderr)
            else:
                print("No barcodes of any type detected", file=sys.stderr)

        return result

    # Use first result
    barcode = barcodes[0]

    if verbose:
        print(f"Found {len(barcodes)} barcode(s)", file=sys.stderr)
        print(f"Format: {barcode.format}", file=sys.stderr)
        print(f"Content type: {barcode.content_type}", file=sys.stderr)
        if hasattr(barcode, 'is_valid') and not barcode.is_valid:
            print(f"Warning: Barcode may be partially decoded", file=sys.stderr)

    result["success"] = True
    result["format"] = str(barcode.format)
    result["text"] = barcode.text

    # Get raw bytes
    if hasattr(barcode, 'bytes'):
        result["bytes"] = list(barcode.bytes)
    elif hasattr(barcode, 'raw_bytes'):
        result["bytes"] = list(barcode.raw_bytes)

    # Get position
    if hasattr(barcode, 'position'):
        pos = barcode.position
        result["position"] = {
            "top_left": (pos.top_left.x, pos.top_left.y),
            "top_right": (pos.top_right.x, pos.top_right.y),
            "bottom_right": (pos.bottom_right.x, pos.bottom_right.y),
            "bottom_left": (pos.bottom_left.x, pos.bottom_left.y)
        }

    return result


def decode_from_raw_modules(modules: list[list[bool]], verbose: bool = False) -> dict:
    """
    Decode Aztec barcode from raw module grid.

    Args:
        modules: 2D list of booleans (True = dark module)
        verbose: Print debug info

    Returns same dict as decode_aztec()
    """
    result = {
        "success": False,
        "text": None,
        "bytes": None,
        "format": None,
        "position": None,
        "error": None
    }

    try:
        import zxingcpp
    except ImportError:
        result["error"] = "zxing-cpp not installed"
        return result

    try:
        from PIL import Image
    except ImportError:
        result["error"] = "Pillow not installed"
        return result

    # Render modules to image with quiet zone
    size = len(modules)
    quiet_zone = 4
    module_size = 10

    img_size = (size + 2 * quiet_zone) * module_size
    img = Image.new('RGB', (img_size, img_size), 'white')
    pixels = img.load()

    for y in range(size):
        for x in range(size):
            if modules[y][x]:
                # Draw dark module
                px = (quiet_zone + x) * module_size
                py = (quiet_zone + y) * module_size
                for dy in range(module_size):
                    for dx in range(module_size):
                        pixels[px + dx, py + dy] = (0, 0, 0)

    if verbose:
        print(f"Rendered {size}x{size} modules to {img_size}x{img_size} image", file=sys.stderr)

    # Now decode
    reader_options = zxingcpp.ReaderOptions()
    reader_options.formats = zxingcpp.BarcodeFormat.Aztec
    reader_options.try_harder = True

    try:
        barcodes = zxingcpp.read_barcodes(img, reader_options)
    except Exception as e:
        result["error"] = f"Decode error: {e}"
        return result

    if not barcodes:
        result["error"] = "No Aztec barcode detected"
        return result

    barcode = barcodes[0]
    result["success"] = True
    result["format"] = str(barcode.format)
    result["text"] = barcode.text

    if hasattr(barcode, 'bytes'):
        result["bytes"] = list(barcode.bytes)

    return result


def main():
    parser = argparse.ArgumentParser(
        description="Decode Aztec barcode from image using zxing-cpp"
    )
    parser.add_argument("image", help="Path to image file")
    parser.add_argument("-v", "--verbose", action="store_true",
                       help="Print verbose diagnostic output")
    parser.add_argument("--raw", action="store_true",
                       help="Output raw bytes as hex instead of text")
    parser.add_argument("--json", action="store_true",
                       help="Output result as JSON")

    args = parser.parse_args()

    # Check image exists
    if not Path(args.image).exists():
        print(f"Error: File not found: {args.image}", file=sys.stderr)
        sys.exit(1)

    result = decode_aztec(args.image, verbose=args.verbose)

    if args.json:
        print(json.dumps(result, indent=2))
        sys.exit(0 if result["success"] else 1)

    if result["success"]:
        if args.raw and result["bytes"]:
            print("Bytes:", " ".join(f"{b:02x}" for b in result["bytes"]))
        else:
            print(result["text"])
        sys.exit(0)
    else:
        print(f"Error: {result['error']}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

#!/bin/bash
# PDL::Graphics::Cairo OSXバックエンド ビルドスクリプト
set -e

echo "=== Building pdlcairo_viewer ==="
clang -fobjc-arc \
    -framework Cocoa \
    -o pdlcairo_viewer \
    pdlcairo_viewer.m

echo "=== Done ==="
ls -lh pdlcairo_viewer

# Video Size Limiter

A small native macOS app written in Swift, using SwiftUI and AppKit. Requires macOS 14 or newer and a local installation of **ffmpeg + ffprobe**. It discovers Homebrew, Nix, and PATH installations automatically; videos never leave your Mac.

## Use

1. Open **Video Size Limiter.app**.
2. Drop one video onto the window, click **Choose video…** (⌘O), or copy a file in Finder and press **⌘V**. Pasting an absolute path or a file URL works too. You can also drop a video on the Dock icon or use Finder's Open With.
3. Enter the maximum size in **MB** and press Return. One MB is 1,000,000 bytes. Decimal sizes and a decimal comma are supported.
4. The app verifies the finished file is **strictly below** the limit, saves it in `~/Documents/Videos`, and selects it in Finder.

Outputs use `original-name-compressed.ext`, adding a numeric suffix when necessary. Originals are untouched. A file already below the limit is copied without re-encoding. Cancel terminates FFmpeg and removes the partial output.

## Compression behavior

- Preserves the video codec, dimensions, pixel format, timing, and original container extension. No resizing or frame-rate reduction is requested. Automatic rotation is disabled so pixels are not transformed; FFmpeg carries the source display metadata forward.
- Copies audio, subtitles, attachments, and other streams rather than re-encoding them; requests preservation of metadata and chapters. Container-specific/private metadata is subject to FFmpeg's remuxing support. Encoding profile, encoder-specific settings, and compressed bitstream naturally change when re-encoding video.
- Supports size-targeted H.264, HEVC, VP8, VP9, AV1, MPEG-4 Part 2, and MPEG-2. Other codecs and files with multiple main video tracks produce an explicit error rather than silently changing codec or dropping tracks.
- H.264, VP8, VP9, and MPEG-4 use two-pass encoding. Other supported codecs use bitrate encoding with measured retries. A 3% initial safety allowance covers container overhead; measured overshoots trigger lower-bitrate retries. Final byte size and basic stream properties are checked before publishing the result.
- A target too small to preserve the audio/duration may be impossible. Increase the limit if asked. Quality at any given size depends on the source codec and content.
- Requires the matching software encoders in your FFmpeg build (`libx264`, `libx265`, `libvpx`, `libvpx-vp9`, or `libsvtav1`). The app reports FFmpeg's error when an encoder or container feature is unavailable.

## Build and test

With Xcode's Swift toolchain installed:

```sh
swift test
./scripts/build-app.sh
open 'build/Video Size Limiter.app'
```

The build script creates an ad-hoc signed local app. It uses the current Mac's architecture and installed FFmpeg; it is not a self-contained notarized distribution. To install locally, copy the app to `~/Applications`.

The package can also be opened directly in Xcode. `VideoSizeCore` contains the compression engine, and `VideoSizeLimiter` contains the native UI. Integration tests generate synthetic media and verify actual size, codec, frame rate, dimensions, unchanged audio packets, copying, collision handling, invalid input, and cancellation.

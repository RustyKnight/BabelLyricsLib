# For a 2-step silence-based workflow, the key FFmpeg parameters are:

1. Silence detection (silencedetect)
• noise (n=): silence threshold (e.g., -35dB to -45dB)
• duration (d=): minimum silence length to count (e.g., 0.3 to 1.0 sec)
• mono (m=1): detect per channel instead of mixed signal (useful for uneven stereo)

`ffmpeg -i input.wav -af silencedetect=n=-40dB:d=0.5 -f null -`

2. Segmentation (split at detected times)
• -f segment: enable segment muxer
• -segment_times: comma-separated split points from step 1
• -reset_timestamps 1: each segment starts at 00:00
• -c copy (fast, no re-encode) or audio codec options if re-encoding
• -map 0:a:0: choose the audio stream explicitly

```
ffmpeg -i input.wav -map 0:a:0 -f segment \
  -segment_times 12.4,28.9,47.2 \
  -reset_timestamps 1 -c copy out_%03d.wav
```

Practical tuning: start with n=-40dB:d=0.5; if over-splitting, lower sensitivity (-35dB) or increase d (0.8+).
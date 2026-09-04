/** @import { Orchestration, Task, Artifact } from "../types.js" */

/** @returns {string[]} */
function audioCmd(opts) {
  return [
    "ffmpeg",
    "-nostdin",
    "-hide_banner",
    ["-loglevel", "warning"],
    "-y",
    ["-i", "artifact.file"],

    "-vn",

    ["-c:a", "aac"],
    ["-b:a", opts.ba],
    ["-ar", opts.ar],
    ["-ac", opts.ac],

    ["-f", "hls"],
    ["-hls_time", "6"],
    ["-hls_playlist_type", "vod"],
    ["-hls_list_size", "0"],
    ["-hls_segment_type", "mpegts"],
    ["-hls_flags", "single_file+independent_segments"],
    ["-hls_segment_filename", `${opts.fileStem}.ts`],

    `${opts.fileStem}.m3u8`,
  ].flat();
}

/** @returns {string[]} */
function videoCmd(opts) {
  return [
    "ffmpeg",
    "-nostdin",
    "-hide_banner",
    ["-loglevel", "warning"],
    "-y",
    ["-i", "artifact.file"],

    ["-vf", `scale=${opts.scale}:flags=lanczos,fps=30,setsar=1`],

    "-an",

    ["-pix_fmt", "yuv420p"],
    ["-c:v", "libx264"],
    ["-preset:v", "slow"],
    ["-profile:v", "high"],
    ["-g:v", "60"],
    ["-keyint_min:v", "60"],
    ["-sc_threshold:v", "0"],
    ["-b:v", opts.bv],
    ["-maxrate:v", opts.maxratev],
    ["-bufsize:v", opts.bufsizev],

    ["-force_key_frames", "expr:gte(t,n_forced*2)"],

    ["-f", "hls"],
    ["-hls_time", "6"],
    ["-hls_playlist_type", "vod"],
    ["-hls_list_size", "0"],
    ["-hls_segment_type", "mpegts"],
    ["-hls_flags", "single_file+independent_segments"],
    ["-master_pl_name", `${opts.fileStem}-master.m3u8`],
    ["-hls_segment_filename", `${opts.fileStem}.ts`],

    `${opts.fileStem}.m3u8`,
  ].flat();
}

const variants = {
  AUDIO: {
    cmdBuilder: audioCmd,
    opts: {
      ba: "192k",
      ar: "48000",
      ac: "2",
      fileStem: "audio",
    },
  },
  "480P": {
    cmdBuilder: videoCmd,
    opts: {
      scale: "854:480",
      bv: "1400k",
      maxratev: "1498k",
      bufsizev: "2800k",
      fileStem: "480p",
    },
  },
  "720P": {
    cmdBuilder: videoCmd,
    opts: {
      scale: "1280:720",
      bv: "2800k",
      maxratev: "2996k",
      bufsizev: "5600k",
      fileStem: "720p",
    },
  },
  "1080P": {
    cmdBuilder: videoCmd,
    opts: {
      scale: "1920:1080",
      bv: "5000k",
      maxratev: "5350k",
      bufsizev: "10000k",
      fileStem: "1080p",
    },
  },
  "1440P": {
    cmdBuilder: videoCmd,
    opts: {
      scale: "2560:1440",
      bv: "8000k",
      maxratev: "8560k",
      bufsizev: "16000k",
      fileStem: "1440p",
    },
  },
  "2160P": {
    cmdBuilder: videoCmd,
    opts: {
      scale: "3840:2160",
      bv: "25000k",
      maxratev: "26750k",
      bufsizev: "50000k",
      fileStem: "2160p",
    },
  },
};

/**
 * @param {Task} _task
 * @returns {Orchestration}
 */
export default function (_task) {
  return {
    Preset: {
      Name: "Standard Podcast 2026 v1",
      PossibleLabels: Object.keys(variants),
    },
    VariantSubtasks: Object.keys(variants).map((k) => {
      const variant = variants[k];

      return {
        PresetLabel: k,
        FileStem: variant.opts.fileStem,
        FFmpegCommandParts: variant.cmdBuilder(variant.opts),
      };
    }),
  };
}

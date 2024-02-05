import { join as pathJoin } from "node:path";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createInterface } from "node:readline";
import { unlinkSync, createReadStream } from "node:fs";
import { writeArtifact } from "porter-util";

const DEFAULT_MIN_VALUE = 0.025;
const DEFAULT_MIN_DURATION = 0.2;

function createMetadataFile(inputFilePath, outputFilePath, frequency) {
  return new Promise((resolve, reject) => {
    const start = process.hrtime();

    const filterString = [
      "pan=mono|c0=.5*c0+.5*c1",
      "volume=volume=1.0",
      `bandpass=frequency=${frequency}:width_type=q:width=3`,
      "astats=metadata=1:reset=1",
      `ametadata=key=lavfi.astats.Overall.Max_level:mode=print:file=${outputFilePath}`,
    ].join(",");

    const childProc = spawn(
      "/opt/bin/ffmpeg",
      ["-i", inputFilePath, "-af", filterString, "-f", "null", "-"],
      {
        env: process.env,
        cwd: tmpdir(),
      },
    );

    childProc.stdout.on("data", (buffer) => console.info(buffer.toString()));
    childProc.stderr.on("data", (buffer) => console.error(buffer.toString()));

    childProc.on("exit", (code, signal) => {
      const end = process.hrtime(start);
      console.log(
        JSON.stringify({
          msg: "Finished FFmpeg",
          duration: `${end[0]} s ${end[1] / 1000000} ms`,
        }),
      );

      if (code || signal) {
        reject(new Error(`FFmpeg failed with ${code || signal}`));
      } else {
        resolve();
      }
    });
  });
}

async function getRangesFromMetadataFile(filePath, minValue, minDuration) {
  const ranges = [];

  const reader = createInterface({
    input: createReadStream(filePath),
    crlfDelay: Infinity,
  });

  let timeBuffer;
  let rangeBuffer;

  reader.on("line", (line) => {
    if (line.startsWith("frame:")) {
      timeBuffer = Number(line.split("pts_time:")[1]);
    }

    if (line.startsWith("lavfi.astats.Overall.Max_level=")) {
      const level = Number(line.split("=")[1]);

      if (level >= minValue) {
        // This line represents a tone

        if (!rangeBuffer) {
          // Start a new range with sensible default values
          rangeBuffer = {
            Start: timeBuffer,
            End: timeBuffer,
            Minimum: level,
            Maximum: level,
          };
        } else {
          // Update values when working on a continuous range
          rangeBuffer.End = timeBuffer;
          rangeBuffer.Minimum = Math.min(rangeBuffer.Minimum, level);
          rangeBuffer.Maximum = Math.max(rangeBuffer.Maximum, level);
        }
      } else {
        // This line is not tone

        // If there's no active range, do nothing
        if (!rangeBuffer) {
          return;
        }

        // If the range is long enough to record, add it
        if (rangeBuffer.End - rangeBuffer.Start > minDuration) {
          ranges.push(rangeBuffer);
        }

        // Start a new range for the next line
        rangeBuffer = undefined;
      }
    }
  });

  await once(reader, "close");

  return ranges;
}

export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  const artifactTmpPath = await writeArtifact(event, context);

  const frequency = event.Task.Frequency;
  const minValue = event.Task?.Threshold?.Value || DEFAULT_MIN_VALUE;
  const minDuration = event.Task?.Threshold?.Duration || DEFAULT_MIN_DURATION;

  const metadataFileTmpPath = pathJoin(
    tmpdir(),
    `${context.awsRequestId}.meta`,
  );
  await createMetadataFile(artifactTmpPath, metadataFileTmpPath, frequency);

  const ranges = await getRangesFromMetadataFile(
    metadataFileTmpPath,
    minValue,
    minDuration,
  );

  unlinkSync(artifactTmpPath);
  unlinkSync(metadataFileTmpPath);

  return {
    Task: "DetectTone",
    Threshold: {
      Value: minValue,
      Duration: minDuration,
    },
    Tone: { Frequency: frequency, Ranges: ranges },
  };
};

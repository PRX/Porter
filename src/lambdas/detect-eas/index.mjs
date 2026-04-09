import { unlinkSync } from "node:fs";
import { detect } from "@prx.org/eas-detect";
import { writeArtifact } from "porter-util";

export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  const artifactTmpPath = await writeArtifact(event, context);

  const fskMode = event?.FSKMode === "Sensitive" ? "sensitive" : "default";
  const result = await detect(artifactTmpPath, { fskMode });

  unlinkSync(artifactTmpPath);

  return {
    Task: "DetectEas",
    EAS: result,
    ...(fskMode === "sensitive" && { FSKMode: event?.FSKMode }),
  };
};

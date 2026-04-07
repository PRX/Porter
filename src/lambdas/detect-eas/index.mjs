import { unlinkSync } from "node:fs";
import { detect } from "@prx.org/eas-detect";
import { writeArtifact } from "porter-util";

export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  const artifactTmpPath = await writeArtifact(event, context);

  const result = await detect(artifactTmpPath);

  unlinkSync(artifactTmpPath);

  return {
    Task: "DetectEas",
    EAS: result,
  };
};

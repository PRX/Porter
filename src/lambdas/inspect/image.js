import sharp from "sharp";

/** @typedef {import('./index.js').InspectTask} InspectTask */
/** @typedef {import('./tags.js').Tag} Tag */

/**
 * @typedef {object} ImageInspection
 * @property {number} [Width]
 * @property {number} [Height]
 * @property {string} [Format]
 * @property {Tag[]} [Tags]
 */

/**
 * @typedef {object} SharpComment
 * @property {string} keyword
 * @property {string} text
 */

function sharpMetadata(filePath) {
  return new Promise((resolve, reject) => {
    sharp(filePath)
      .metadata()
      .then((metadata) => resolve(metadata))
      .catch((e) => reject(e));
  });
}

/**
 * @param {InspectTask} task
 * @param {string} filePath
 */
export async function inspect(task, filePath) {
  /** @type {ImageInspection} */
  const inspection = {};

  try {
    const meta = await sharpMetadata(filePath);

    if (meta) {
      Object.assign(inspection, {
        ...(meta.width && { Width: +meta.width }),
        ...(meta.height && { Height: +meta.height }),
        ...(meta.format && { Format: meta.format }),
      });
    }

    /** @type {SharpComment[]} */
    const tags = meta?.comments;

    // Find tags in the metadata comments that match the criteria
    if (tags && task.IncludeMetadata) {
      const keyMatches = task.IncludeMetadata?.Keys?.StringMatches;
      let keysRegex = null;
      let valuesRegex = null;
      if (keyMatches) {
        keysRegex = new RegExp(keyMatches);
      }
      const valueMatches = task.IncludeMetadata.Values?.StringMatches;
      if (valueMatches) {
        valuesRegex = new RegExp(valueMatches);
      }

      inspection.Tags = [];

      // use each regex to extract only the matching tags
      tags.forEach((tag) => {
        const key = tag.keyword;
        const value = tag.text;
        if (keysRegex?.test(key)) {
          inspection.Tags.push({ key, value });
        } else if (valuesRegex?.test(value)) {
          inspection.Tags.push({ key, value });
        }
      });
    }
  } catch (error) {
    console.log(error);
  }

  // Only return the inspection result object if any keys were added
  if (Object.keys(inspection).length) {
    return inspection;
  }

  console.log("Image inspection yielded no results");
  return null;
}

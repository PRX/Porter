const sharp = require('sharp');

/** @typedef {import('./index').InspectTask} InspectTask */

/**
 * @typedef {object} ImageInspection
 * @property {number} [Width]
 * @property {number} [Height]
 * @property {string} [Format]
 */

function sharpMetadata(filePath) {
  return new Promise((resolve, reject) => {
    sharp(filePath)
      .metadata()
      .then((metadata) => resolve(metadata))
      .catch((e) => reject(e));
  });
}

module.exports = {
  /**
   * @param {InspectTask} task
   * @param {string} filePath
   */
  inspect: async function inspect(task, filePath) {
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
    } catch (error) {
      console.log(error);
    }

    // Only return the inspection result object if any keys were added
    if (Object.keys(inspection).length) {
      return inspection;
    }

    console.log('Image inspection yielded no results');
    return null;
  },
};

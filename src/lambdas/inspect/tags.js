/** @typedef {import('./index.js').MetadataRequest} MetadataRequest */

/**
 * @typedef {object} Tag
 * @property {string} key
 * @property {string} value
 */

/**
 * Converts FFprobe tags to the inspection Tag format
 * @param {*} tags
 * @param {MetadataRequest} includeMetadata
 * @returns {Tag[]}
 */
export function ffprobeTags(tags, includeMetadata) {
  /** @type {Tag[]} */
  const result = [];

  const keyMatches = includeMetadata?.Keys?.StringMatches;
  let keysRegex = null;
  let valuesRegex = null;
  if (keyMatches) {
    keysRegex = new RegExp(keyMatches);
  }
  const valueMatches = includeMetadata?.Values?.StringMatches;
  if (valueMatches) {
    valuesRegex = new RegExp(valueMatches);
  }

  // use each regex to extract only the matching tags
  Object.keys(tags).forEach((key) => {
    const value = tags[key];
    if (keysRegex?.test(key)) {
      result.push({ key, value });
    } else if (valuesRegex?.test(value)) {
      result.push({ key, value });
    }
  });

  return result;
}

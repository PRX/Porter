/**
 * Tries to convert the input value to a number. If the function does return a
 * value, it will be a number. If it can't figure out how to make the input a
 * number, it doesn't return anything.
 * @param {*} val
 * @returns {number}
 */
export function nmbr(val) {
  // Reflect a number input
  if (typeof val === "number") {
    return val;
  }

  // Look for strings like "24000/1001", and do the division safely
  const rex = /^(-?[0-9]+(?:\.[0-9]+)?)(\/)(-?[0-9]+(?:\.[0-9]+)?)$/;
  if (typeof val === "string" && val.match(rex)) {
    const match = val.match(rex);
    return +match[1] / +match[3];
  }

  // Look for integer and decimal strings and convert to numbers
  if (typeof val === "string" && val.match(/^(-?[0-9]+(\.[0-9]+)?)$/)) {
    return +val;
  }

  return null;
}

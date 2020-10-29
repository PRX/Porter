module.exports = {
  /**
   * Tries to convert the input value to a number. If the function does return a
   * value, it will be a number. If it can't figure out how to make the input a
   * number, it doesn't return anything.
   * @param {*} val
   * @returns {number}
   */
  nmbr: function nmbr(val) {
    // Reflect a number input
    if (typeof val === 'number') {
      return val;
    }

    // Look for strings like "24000/1001", and do the division safely
    if (
      typeof val === 'string' &&
      val.match(/^-?[0-9]+(\.[0-9]+)?\/-?[0-9]+(\.[0-9]+)?$/)
    ) {
      const match = val.match(/^-?[0-9]+(\.[0-9]+)?\/-?[0-9]+(\.[0-9]+)?$/);
      return +match[1] / +match[3];
    }

    //
    if (typeof val === 'string' && val.match(/^(-?[0-9]+(\.[0-9]+)?)$/)) {
      return +val;
    }

    return null;
  },
};

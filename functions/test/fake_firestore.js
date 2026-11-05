'use strict';

/**
 * Just enough of the Admin SDK Firestore surface for pipeline.js:
 * `collection(name).doc(id)` (nestable), `ref.get()`, `ref.set()`, and
 * `runTransaction(fn)` with `tx.get` / `tx.set(ref, data, {merge})`.
 *
 * Transactions apply their writes when `fn` resolves (all-or-nothing, like the
 * real thing) and can be interleaved with outside writes through `hooks`, which
 * is how the mid-render race is reproduced.
 */
function makeFakeFirestore(seed = {}) {
  const docs = new Map(Object.entries(seed));

  const merge = (path, data, opts) => {
    const base = opts && opts.merge ? docs.get(path) || {} : {};
    const next = {...base};
    for (const [k, v] of Object.entries(data)) {
      // FieldValue.delete() sentinels and friends: treat any non-plain class
      // instance whose name says delete as a delete.
      if (v && typeof v === 'object' && v.constructor && /Delete/i.test(v.constructor.name)) {
        delete next[k];
      } else {
        next[k] = v;
      }
    }
    docs.set(path, next);
  };

  const snapshot = (path) => ({
    exists: docs.has(path),
    id: path.split('/').pop(),
    data: () => (docs.has(path) ? {...docs.get(path)} : undefined),
  });

  const docRef = (path) => ({
    path,
    id: path.split('/').pop(),
    collection: (name) => collectionRef(`${path}/${name}`),
    get: async () => snapshot(path),
    set: async (data, opts) => merge(path, data, opts),
  });

  const collectionRef = (path) => ({
    path,
    doc: (id) => docRef(`${path}/${id}`),
  });

  return {
    docs,
    transactions: 0,
    collection: collectionRef,
    /** Read a doc's data synchronously (test helper). */
    peek: (path) => (docs.has(path) ? {...docs.get(path)} : null),
    async runTransaction(fn) {
      this.transactions += 1;
      const writes = [];
      const tx = {
        get: async (ref) => snapshot(ref.path),
        set: (ref, data, opts) => {
          writes.push([ref.path, data, opts]);
          return tx;
        },
      };
      const result = await fn(tx);
      for (const [path, data, opts] of writes) merge(path, data, opts);
      return result;
    },
  };
}

module.exports = {makeFakeFirestore};

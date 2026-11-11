'use strict';

/**
 * Arena moderation: user reports (App Store guideline 1.2).
 *
 * The app's "⋯ > Report post" writes one document per (post, reporter):
 *
 *   reports/{postId}_{reporterUid}
 *     {postId, authorId, reporterId, reason, createdAt}
 *
 * firestore.rules makes it create-only, as the signed-in reporter, about a
 * post that exists and is not theirs, with `reason` one of REASONS; nobody can
 * read, edit or delete it from a client. Because the id is fixed per reporter,
 * one person reporting the same post twice is refused at the rules (the second
 * write is an update), so a count of report docs is a count of people.
 *
 * onReportCreated (index.js) logs every report, so the owner sees it in Cloud
 * Logging and can act within the 24 hours the terms promise, and once a post
 * reaches HIDE_AT_REPORTS distinct reporters it takes the post down
 * automatically: `hidden: true` on the post, which
 *   - the app's Arena queue skips (FeedRepositoryImpl.watchQueue);
 *   - firestore.rules treat as private (strangers can't read it by id);
 *   - the public share pages 404 (share_page.js isShareablePost);
 *   - the montage renderer leaves out (contract.js isMontageablePost).
 * No client can set or clear `hidden` (the feed_posts update rules don't list
 * it); un-hiding is an operator action in the console.
 *
 * House posts are logged but never auto-hidden: they are the owner's own
 * seeded content (seed_house_posts.js), and letting three accounts take one
 * down would be a griefing lever, not moderation.
 *
 * `decideReport` is pure; `handleReportInStore` applies it against a small
 * store interface (Firestore in production, an in-memory fake in tests).
 */

const REPORTS = 'reports';
const FEED_POSTS = 'feed_posts';

/** Distinct reporters that take a post down. */
const HIDE_AT_REPORTS = 3;

/** The reasons the app offers; firestore.rules accepts exactly these. */
const REASONS = Object.freeze(['inappropriate', 'spam', 'harassment', 'other']);

/** Doc id of one report: one per (post, reporter). */
const reportDocId = (postId, reporterId) => `${postId}_${reporterId}`;

/**
 * Pure: what to do about a post after a report.
 *
 * @param {{post: object|null, reportCount: number}} args
 * @returns {{hide: boolean, reason: string}}
 */
function decideReport({post, reportCount}) {
  if (!post) return {hide: false, reason: 'post-missing'};
  if (post.hidden === true) return {hide: false, reason: 'already-hidden'};
  if (post.isHouse === true) return {hide: false, reason: 'house-post'};
  if (reportCount < HIDE_AT_REPORTS) return {hide: false, reason: 'below-threshold'};
  return {hide: true, reason: 'threshold-reached'};
}

/**
 * Handle one new report: count the post's reports, decide, and hide the post
 * when it crosses the threshold.
 *
 * @param {{store: object, report: object, nowIso: () => string}} args
 * @returns {Promise<{postId: string, reportCount: number, hidden: boolean, reason: string}>}
 */
async function handleReportInStore({store, report, nowIso}) {
  const postId = report && typeof report.postId === 'string' ? report.postId : '';
  if (!postId) return {postId, reportCount: 0, hidden: false, reason: 'bad-report'};

  const [post, reporterIds] = await Promise.all([
    store.getPost(postId),
    store.reporterIdsFor(postId),
  ]);
  // Belt and braces: the doc id already makes one report per person.
  const reportCount = new Set(reporterIds.filter(Boolean)).size;
  const decision = decideReport({post, reportCount});
  if (decision.hide) {
    await store.hidePost(postId, {
      hidden: true,
      hiddenAt: nowIso(),
      hiddenBy: 'reports',
      reportCount,
    });
  }
  return {postId, reportCount, hidden: decision.hide, reason: decision.reason};
}

/** The Admin-SDK store for handleReportInStore. */
function firestoreReportStore({db}) {
  return {
    async getPost(postId) {
      const snap = await db.collection(FEED_POSTS).doc(postId).get();
      return snap.exists ? snap.data() : null;
    },
    async reporterIdsFor(postId) {
      const snap = await db.collection(REPORTS).where('postId', '==', postId).get();
      return snap.docs.map((d) => (d.data() || {}).reporterId);
    },
    async hidePost(postId, fields) {
      await db.collection(FEED_POSTS).doc(postId).update(fields);
    },
  };
}

module.exports = {
  REPORTS,
  HIDE_AT_REPORTS,
  REASONS,
  reportDocId,
  decideReport,
  handleReportInStore,
  firestoreReportStore,
};

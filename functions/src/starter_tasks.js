'use strict';

/**
 * The public Starter Pack, as the share pages need it: title, the one-line
 * description shown in a link preview, the clock and the medium.
 *
 * Mirrored from lib/features/tasks/data/datasources/starter_pack_data.dart
 * (test/share_page.test.js pins the ids and durations to that file, and
 * contract.js#STARTER_TASK_IDS to this list). These ten tasks are public by
 * design: everyone's first game, shown cross-game in the Arena, so their
 * posts, montages and /t/ pages are shareable without an owner opt-in.
 */
const STARTER_TASKS = [
  {
    id: 'starter-09-v2',
    title: 'The face of someone who has just remembered the oven is on — in another country',
    description: 'Selfie video. Show us every layer of that realisation arriving, one at a time.',
    durationSeconds: 30,
    medium: 'video',
  },
  {
    id: 'starter-03',
    title: 'Rename a household object',
    description: 'Give any object in the room the name it should have had all along, plus a slogan.',
    durationSeconds: 60,
    medium: 'text',
  },
  {
    id: 'starter-04',
    title: 'Hide in plain sight',
    description: 'A photo of a room with you in it. The crowd must need three seconds to find you.',
    durationSeconds: 120,
    medium: 'photo',
  },
  {
    id: 'starter-10-v2',
    title: 'Your autobiography: the trailer',
    description: 'The title is the last thing you said out loud today. Read line one in a trailer voice.',
    durationSeconds: 30,
    medium: 'video',
  },
  {
    id: 'starter-06',
    title: 'A famous painting, using only what is within arm\'s reach',
    description: 'Recreate a famous painting without moving from where you are.',
    durationSeconds: 180,
    medium: 'photo',
  },
  {
    id: 'starter-01-v2',
    title: 'Egg on a spoon, to the far wall and back',
    description: 'Walk an egg on a spoon to the far wall and back. Narrate it like a nature documentary.',
    durationSeconds: 30,
    medium: 'video',
  },
  {
    id: 'starter-07',
    title: 'A three-line horror story about your fridge',
    description: 'Exactly three lines, based on something actually in your fridge right now.',
    durationSeconds: 90,
    medium: 'text',
  },
  {
    id: 'starter-02-v2',
    title: 'The tallest tower of things that were never meant to be stacked',
    description: 'Film the last three objects going on. A shoe must be involved somewhere.',
    durationSeconds: 60,
    medium: 'video',
  },
  {
    id: 'starter-05-v2',
    title: 'The worst sandwich that is still technically food — and one bite',
    description: 'Every ingredient edible. Film the assembly, then exactly one bite.',
    durationSeconds: 90,
    medium: 'video',
  },
  {
    id: 'starter-08-v2',
    title: 'Wear as many things on your head as possible',
    description: 'Balanced, not tied, not held. Keep filming until they fall.',
    durationSeconds: 60,
    medium: 'video',
  },
];

const BY_ID = new Map(STARTER_TASKS.map((t) => [t.id, t]));

/**
 * The starter task for [id], or null. Accepts the pre-v2 short ids people
 * type or remember (`starter-09` -> `starter-09-v2`), so an old link or a
 * hand-typed one still lands on the live task.
 */
function starterTask(id) {
  if (typeof id !== 'string') return null;
  return BY_ID.get(id) || BY_ID.get(`${id}-v2`) || null;
}

module.exports = {STARTER_TASKS, starterTask};

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/domain/auto_edit.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';

void main() {
  group('AutoEdit.stamp', () {
    // (label, mediaType, elapsed, timer, isLate, expected)
    final cases = <List<Object?>>[
      ['first third of a 90 s timer', SubmissionMediaType.photo, 20, 90, false,
          Stamps.nailedIt],
      ['exactly a third', SubmissionMediaType.photo, 30, 90, false,
          Stamps.nailedIt],
      ['middle third', SubmissionMediaType.photo, 45, 90, false,
          Stamps.noRegrets],
      ['exactly two thirds is still the middle', SubmissionMediaType.photo, 60,
          90, false, Stamps.noRegrets],
      ['last third', SubmissionMediaType.photo, 75, 90, false,
          Stamps.technically],
      ['late', SubmissionMediaType.photo, 140, 90, true, Stamps.sendHelp],
      ['late text entry is still SEND HELP', SubmissionMediaType.text, 200, 90,
          true, Stamps.sendHelp],
      ['middling text entry', SubmissionMediaType.text, 30, 60, false,
          Stamps.art],
      ['text entry with no clock at all', SubmissionMediaType.text, null, null,
          false, Stamps.art],
      ['photo with no clock at all', SubmissionMediaType.photo, null, null,
          false, Stamps.noRegrets],
      ['photo with a clock but no timer', SubmissionMediaType.photo, 30, null,
          false, Stamps.noRegrets],
      ['link entry, middle third', SubmissionMediaType.link, 50, 120, false,
          Stamps.noRegrets],
      ['a zero timer is treated as no timer', SubmissionMediaType.photo, 5, 0,
          false, Stamps.noRegrets],
    ];

    for (final c in cases) {
      test('${c[0]} -> ${c[5]}', () {
        expect(
          AutoEdit.stamp(
            mediaType: c[1] as SubmissionMediaType,
            elapsedSeconds: c[2] as int?,
            timerSeconds: c[3] as int?,
            isLate: c[4] as bool,
          ),
          c[5],
        );
      });
    }

    test('only ever returns a real stamp', () {
      for (final media in SubmissionMediaType.values) {
        for (final elapsed in [null, 0, 10, 300]) {
          final stamp = AutoEdit.stamp(
            mediaType: media,
            elapsedSeconds: elapsed,
            timerSeconds: 90,
            isLate: elapsed != null && elapsed > 120,
          );
          expect(Stamps.values, contains(stamp));
        }
      }
    });
  });

  group('AutoEdit.caption', () {
    test('joins the twist and the timing', () {
      expect(
        AutoEdit.caption(
          twist: 'Nothing in the tower may be a box.',
          elapsedSeconds: 41,
          timerSeconds: 120,
          isLate: false,
        ),
        'Nothing in the tower may be a box. · Done in 41 s',
      );
    });

    test('a late entry says how far past the grace deadline it was', () {
      // 90 s timer + 30 s grace = late from 120 s; 132 s is 12 s past that.
      expect(
        AutoEdit.caption(
          twist: 'No hands in the photo.',
          elapsedSeconds: 132,
          timerSeconds: 90,
          isLate: true,
        ),
        'No hands in the photo. · LATE by 12 s',
      );
    });

    test('a late entry never claims to be late by zero seconds', () {
      expect(
        AutoEdit.caption(
          twist: null,
          elapsedSeconds: 120,
          timerSeconds: 90,
          isLate: true,
        ),
        'LATE by 1 s',
      );
    });

    test('no twist leaves just the timing', () {
      expect(
        AutoEdit.caption(
          twist: null,
          elapsedSeconds: 8,
          timerSeconds: 30,
          isLate: false,
        ),
        'Done in 8 s',
      );
    });

    test('a blank twist counts as no twist', () {
      expect(
        AutoEdit.caption(
          twist: '   ',
          elapsedSeconds: 8,
          timerSeconds: 30,
          isLate: false,
        ),
        'Done in 8 s',
      );
    });

    test('no clock leaves just the twist', () {
      expect(
        AutoEdit.caption(
          twist: 'The last line must be a single word.',
          elapsedSeconds: null,
          timerSeconds: 90,
          isLate: false,
        ),
        'The last line must be a single word.',
      );
    });

    test('neither leaves an empty caption', () {
      expect(
        AutoEdit.caption(
          twist: null,
          elapsedSeconds: null,
          timerSeconds: null,
          isLate: false,
        ),
        '',
      );
    });

    test('the grace period is the documented 30 s', () {
      expect(AutoEdit.graceSeconds, 30);
    });
  });
}

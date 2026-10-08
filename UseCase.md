User will follow these steps to use this application.
* Step 1: Open and add video files under test/e2e/videoSource to sourcefiles list.
* Step 2: Play the first file in sourcefiles list.
* Step 3: Click mark button at 11 seconds of video file test1 and add description test1_mark, click okay to add mark and resume play.
* Step 4: Click mark button at 11 seconds of video file test2 and add description test2_mark, click okay to add mark and resume play.
* Step 5: Click mark button at 11 seconds of video file test3 and add description test3_mark, click okay to add mark and resume play.
* Step 6: Click mark button at 11 seconds of video file test4 and add description test4_mark, click okay to add mark and resume play.
* Step 7: All video files played. Check timeslots list. There should be 4 records.
* Step 8: Click make button next to the speed control.
* Step 9: Generate transition video files for each timeslot record, 
** transition video file will be stored under temp folder, name as test1_mark_transition.mp4, etc.
** transition video file last 1 second, 720p. 
** transition video file contains timeslot description name in the screen center.
* Step 10: Slice sub video file according the timeslot record. 
** start time equals to 10 seconds earlier than the record time.
** resolution 720p.
** name as test1_mark_sub.mp4
* Step 11: Combine all those sub video files to a single video file.
** test/e2e/videoSource/startup.mp4 + test1_mark_transition.mp4 + test1_mark_sub.mp4 + ... + test4_mark_sub.mp4
** result will be named as final.mp4 and stored under temp folder.
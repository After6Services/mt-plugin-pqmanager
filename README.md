# Publish Queue Manager plugin for Movable Type

This plugin provides a simple user interface in the Movable Type administrative
system to view, change priority, and delete publishing jobs from the built-in
"Publish Queue" system -- a system by which files are published in the
background. Keeping an eye on what is publishing is a great way to understand
what is happening at any given time!

If you're using this plugin you are likely working towards a well-optimized
system, and one of the things you want to discourage other administrators and
permissioned users from doing is republishing an entire blog. This plugin
provides you opportunity to specify blogs and a message to warn users when they
click the republish popup. Additionally, large republishing jobs (started from
the republish popup window) are logged to the Activity Log so you can see their
record.

# Prerequisites

* Movable Type 5.2.6 or later
* Movable Type 6 or later

Compatibility with Movable Type 4.2x and 4.3x can be found in
[version 1.2.5](https://github.com/endevver/mt-plugin-pqmanager/releases).

# Installation

To install this plugin follow the instructions found here:

http://tinyurl.com/easy-plugin-install

# Usage

The Publish Queue Manager provides an at-a-glance review of the contents of the
Publish Queue by adding a "PQ Jobs" menu to Movable Type. Information provided:

* A highlighted count of the number of publishing-related jobs in the queue.
* How old the most recent publish job was added.
* How long ago the oldest publish job was added.
* A quick look at any non-publishing workers in the queue.
* If there are any items in the task error log.

Click any of these many options to get to the full Publish Queue listing screen.

(MT4 users: find Manage > Publish Queue Jobs in the System Dashboard, or
Publish Queue Jobs in the System Overview menu in the upper-right of the
screen.)

A spinning icon displayed next to the Priority column indicates that job is
currently being processed.

Deleting jobs and changing their priority is pretty simple: select a job (or
jobs) and click the Delete button or choose the More Actions... Change Priority
option.

Clicking the "Error log" menu option provides insight into why and which jobs
have failed. This information is also recorded in the Activity Log, however it's
often difficult to pull the data out of there. Use the message provided to help
track down errors so they can be fixed. Error records can be deleted, and
deleting all records will cause the "Error log" menu item to not appear until a
new error has been recorded.

Configure whole blog publish warnings at the system level, by going to Tools >
Plugins and choosing Publish Queue Manager > Settings. Select the blogs you want
to warn users not to republish and specify a message to warn them with. The
default warning message:

> Are you sure you want to do this? There are good reasons to republish an
entire archive or a whole blog, but in a well-optimized system it is rarely
necessary. Check with the site administrator to see if there's a better way.

Republish actions are logged to the Activity Log. If you'd like to filter these,
look for the class `pqmanager` and the category `publish`.

# Support

Please post your bugs, questions and comments to Publish Queue Manager Github
Issues:

  https://github.com/endevver/mt-plugin-pqmanager/issues

# Resources

Movable Type: http://movabletype.org/

# License

Publish Queue Manager is licensed under the GPL.
Copyright 2008, Six Apart, Ltd.
Copyright 2009, Byrne Reese.
Copyright 2009-2014, Endevver LLC

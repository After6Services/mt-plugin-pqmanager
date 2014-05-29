# Publish Queue Manager plugin for Movable Type

This plugin provides a simple user interface in the Movable Type administrative
system to view, change priority, and delete publishing jobs from the built-in
"Publish Queue" system -- a system by which files are published in the
background. Keeping an eye on what is publishing is a great way to understand
what is happening at any given time!

# Prerequisites

* Movable Type 5.2.6 or later
* Movable Type 6 or later

Compatibility with Movable Type 4.2x and 4.3x can be found in [version 1.2.5](https://github.com/endevver/mt-plugin-pqmanager/releases).

# Installation

To install this plugin follow the instructions found here:

http://tinyurl.com/easy-plugin-install

# Usage

The Publish Queue Manager provides an at-a-glance review of the contents of the Publish Queue by adding a "PQ Jobs" menu to Movable Type. Information provided:

* A highlighted count of the number of publishing-related jobs in the queue.
* How old the most recent publish job was added.
* How long ago the oldest publish job was added.
* A quick look at any non-publishing workers in the queue.

Click any of these many options to get to the full Publish Queue listing screen.

(MT4 users: find Manage > Publish Queue Jobs in the System Dashboard, or
Publish Queue Jobs in the System Overview menu in the upper-right of the
screen.)

A spinning icon displayed next to the Priority column indicates that job is
currently being processed.

Deleting jobs and changing their priority is pretty simple: select a job (or
jobs) and click the Delete button or choose the More Actions... Change Priority
option.

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

# Publish Queue Manager Plugin for Movable Type
# Author: Byrne Reese, byrne at majordojo dot com
# Copyright (C) 2008 Six Apart, Ltd.
package PQManager::Plugin;

use strict;
use MT::Util qw( relative_date format_ts epoch2ts ts2epoch iso2ts decode_js );
use warnings;
use Carp;

use MT::TheSchwartz;
use MT::TheSchwartz::Error;

# The system config settings
sub system_config {
    my ($plugin, $param, $scope) = @_;
    my $app = MT->instance;
    my $options = '';

    # We want to sort both websites and blogs in the same way: A-Z.
    my $args = {
        sort      => 'name',   # Sort alphabetically by template name.
        direction => 'ascend',
    };

    # Move any previously-selected blog IDs into an array.
    my @warning_blog_ids;
    if ( ref $param->{republish_warning_blog_ids} eq 'ARRAY' ) {
        (@warning_blog_ids) = @{$param->{republish_warning_blog_ids}};
    }
    else {
        push @warning_blog_ids, $param->{republish_warning_blog_ids};
    }

    # Put together a list of blogs and websites the user can select from.
    my $website_iter = $app->model('website')->load_iter(
        {
            class => 'website',
        },
        $args
    );

    # Order the options by website-blog/parent-child and alphabetically so that
    # it's easy to read.
    while ( my $website = $website_iter->() ) {
        my $website_id = $website->id;
        my $selected = (grep /^$website_id$/, @warning_blog_ids)
            ? ' selected' : '';

        $options .= '<option value="' . $website_id . '"' . $selected . '>'
            . $website->name . "</option>\n";

        my $blog_iter = $app->model('blog')->load_iter(
            {
                class     => 'blog',
                parent_id => $website_id,
            },
            $args
        );

        while ( my $blog = $blog_iter->() ) {
            my $blog_id = $blog->id;
            $selected = (grep /^$blog_id$/, @warning_blog_ids)
                ? ' selected' : '';

            $options .= '<option value="' . $blog_id . '"' . $selected . '>- '
                . $blog->name . "</option>\n";
        }
    }

    $param->{options} = $options;

    return $plugin->load_tmpl('system_config.mtml');
}

# The "delete" button on the listing screen.
sub mode_delete {
    my $app = shift;
    $app->validate_magic or return;
    my $q = $app->can('query') ? $app->query : $app->param;

    # Grab the Jobs that have been selected.
    my @jobs = $q->param('id');

    # If "select all xxx items" was chosen, select them all.
    if ( $q->param('all_selected') ) {
        my $iter = $app->model('ts_job')->load_iter();
        while ( my $job = $iter->() ) {
            push @jobs, $job->jobid;
        }
    }

    for my $job_id (@jobs) {
        my $job = $app->model('ts_job')->load({jobid => $job_id})
            or next;
        $job->remove or die $job->errstr;
    }

    $app->add_return_arg( deleted => 1 );
    $app->call_return;
}

# The "Change Priority" option on the listing screen.
sub mode_priority {
    my $app = shift;
    $app->validate_magic or return;
    my $q = $app->can('query') ? $app->query : $app->param;

    my $pri = $q->param('itemset_action_input');
    if ($pri !~ /^[0-9]+$/) {
        return $app->error("A priority must be an integer, typically between 1 and 10.");
    }

    # Grab the Jobs that have been selected.
    my @jobs = $q->param('id');

    # If "select all xxx items" was chosen, select them all.
    if ( $q->param('all_selected') ) {
        my $iter = $app->model('ts_job')->load_iter();
        while ( my $job = $iter->() ) {
            push @jobs, $job->jobid;
        }
    }

    for my $job_id (@jobs) {
        my $job = $app->model('ts_job')->load({jobid => $job_id})
            or next;
        $job->priority($pri);
        $job->save or die $job->errstr;
    }

    $app->add_return_arg( priority => $pri );
    $app->call_return;
}

# The MT5 Listing Framework properties.
sub list_properties {
    # Since we're most often specifically working with the PQ items, load that
    # function so that it can be easily referenced anywhere.
    my $worker_func = MT->model('ts_funcmap')->load({
        funcname => 'MT::Worker::Publish',
    });

    return {
        jobid => {
            base    => '__virtual.integer',
            label   => 'Job ID',
            order   => 100,
            display => 'default',
            col     => 'jobid',
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                return $obj && $obj->jobid ? $obj->jobid : 'No jobid found.';
            },
        },
        insert_time => {
            base    => '__virtual.date',
            label   => 'Insert Date',
            display => 'default',
            col     => 'insert_time',
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;

                my $insert_time = '';
                if ($obj && $obj->insert_time) {
                    $insert_time = $obj->insert_time;
                }
                else {
                    return '';
                }

                my $ts          = epoch2ts(undef, $insert_time);
                my $date_format = MT::App::CMS::LISTING_DATE_FORMAT();
                my $is_relative
                    = ( $app->user->date_format || 'relative' ) eq
                    'relative' ? 1 : 0;
                return $is_relative
                    ? relative_date( $ts, time, undef )
                    : format_ts(
                        $date_format,
                        $ts,
                        undef,
                        $app->user ? $app->user->preferred_language : undef
                    );
            },
            bulk_sort => sub {
                my $prop = shift;
                my ($objs, $opts) = @_;
                next unless $objs;

                return sort {
                    my $a_insert_time = $a && $a->insert_time
                        ? $a->insert_time : 0;
                    my $b_insert_time = $b && $b->insert_time
                        ? $b->insert_time : 0;
                    $a_insert_time <=> $b_insert_time;
                } @$objs;
            },
            filter_tmpl => sub {
                ## since __trans macro doesn't work with including itself
                ## recursively, so do translate by hand here.
                my $prop  = shift;
                my $label = '<mt:var name="label">';
                my $tmpl
                    = $prop->use_future
                    ? 'filter_form_future_date'
                    : 'filter_form_date';
                my $opts
                    = $prop->use_future
                    ? '<mt:var name="future_date_filter_options">'
                    : q{<select class="<mt:var name="type">-option filter-date">
    <option value="range"><__trans phrase="is between" escape="js"></option>
    <option value="days"><__trans phrase="is within the last" escape="js"></option>
    <option value="days_older"><__trans phrase="is older than" escape="js"></option>
    <option value="before"><__trans phrase="is before" escape="js"></option>
    <option value="after"><__trans phrase="is after" escape="js"></option>
</select>};
                my $contents
                    = $prop->use_future
                    ? '<mt:var name="future_date_filter_contents">'
                    : q{<span class="date-options">
    <mt:setvarblock name="date_input_from"><input type="text" class="<mt:var name="type">-from text required date" /></mt:setvarblock>
    <mt:setvarblock name="date_input_to"><input type="text" class="<mt:var name="type">-to text required date" /></mt:setvarblock>
    <mt:setvarblock name="date_input_origin"><input type="text" class="<mt:var name="type">-origin text required date" /></mt:setvarblock>
    <mt:setvarblock name="date_input_days"><input type="text" class="<mt:var name="type">-days text required digit days" /></mt:setvarblock>
    <span class="date-option date"><__trans phrase="__FILTER_DATE_ORIGIN" params="<mt:var name="date_input_origin">" escape="js"></span>
    <span class="date-option range"><__trans phrase="[_1] and [_2]" params="<mt:var name="date_input_from">%%<mt:var name="date_input_to">" escape="js"></span>
        <mt:Ignore> Notice that the *hours* are specified here, not days. </mt:Ignore>
    <span class="date-option days days_older"><mt:Var name="date_input_days" escape="js"> hours</span>
</span>};
                return MT->translate(
                    '<mt:var name="[_1]"> [_2] [_3] [_4]',
                    $tmpl, $label, $opts, $contents );
            },
            terms => sub {
                my $prop = shift;
                my ( $args, $db_terms, $db_args ) = @_;
                my $col    = $prop->col;
                my $option = $args->{option};
                my $query;
                my $blog = MT->app ? MT->app->blog : undef;

                # Get the "days" value that was entered. It's not clear to
                # me why this doesn't seem to exist at $args->{days} -- the
                # below snippet is copied from MT::CMS::Filter::save to get
                # the correct value.
                my $app   = MT->instance;
                my $q     = $app->param;
                my $items = [];

                if ( my $items_json = $q->param('items') ) {
                    if ( $items_json =~ /^".*"$/ ) {
                        $items_json =~ s/^"//;
                        $items_json =~ s/"$//;
                        $items_json = decode_js($items_json);
                    }
                    require JSON;
                    my $json = JSON->new->utf8(0);
                    $items = $json->decode($items_json);
                }

                # Finally, the "days" value that the user entered. Remember
                # that this was transformed to hours, so the user thinks they
                # have actually entered number of hours.
                my $hours = $items->[0]->{args}->{days};

                # The `ts_job` table doesn't use a timestamp in the
                # `insert_time` field; it instead uses the epoch value (time in
                # seconds). So, keep the time in the epoch format.
                my $now = time();

                my $from   = $items->[0]->{args}->{from}   || undef;
                my $to     = $items->[0]->{args}->{to}     || undef;
                my $origin = $items->[0]->{args}->{origin} || undef;

                # Ensure that a valid timestamp is created.
                $from =~ s/\D//g;
                $to =~ s/\D//g;
                $origin =~ s/\D//g;
                $from .= '000000' if $from;
                $to   .= '235959' if $to;

                # Convert the timestamp to epoch, because the insert_time field
                # uses epoch. Note that $origin is modified and converted below
                # in the elsif, as needed.
                $from   = ts2epoch(undef, $from) if $from;
                $to     = ts2epoch(undef, $to) if $to;

                if ( 'range' eq $option ) {
                    $query = [
                        '-and',
                        { op => '>=', value => $from },
                        { op => '<=', value => $to },
                    ];
                }
                elsif ( 'days' eq $option ) {
                    $origin = time - ($hours * 60 * 60);
                    $query = [
                        '-and',
                        { op => '>', value => $origin },
                        { op => '<', value => $now },
                    ];
                }
                elsif ( 'days_older' eq $option ) {
                    # Note that time() is used to generate a time since epoch.
                    # Epoch is used in the insert_time table.
                    $origin = time - ($hours * 60 * 60);
                    $query = {
                        op    => '<',
                        value => $origin
                    };
                }
                elsif ( 'before' eq $option ) {
                    $origin = ts2epoch(undef, $origin . '000000');
                    $query = {
                        op    => '<',
                        value => $origin
                    };
                }
                elsif ( 'after' eq $option ) {
                    $origin = ts2epoch(undef, $origin . '235959');
                    $query = {
                        op    => '>',
                        value => $origin
                    };
                }
                elsif ( 'future' eq $option ) {
                    $query = { op => '>', value => $now };
                }
                elsif ( 'past' eq $option ) {
                    $query = { op => '<', value => $now };
                }

                if ( $prop->is_meta ) {
                    $prop->join_meta( $db_args, $query );
                }
                else {
                    return { $col => $query };
                }
            },
        },
        priority => {
            base               => '__virtual.integer',
            label              => 'Priority',
            display            => 'default',
            col                => 'priority',
            order              => 200,
            default_sort_order => 'descend',
            html               => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                my $html = $obj && $obj->priority
                    ? $obj->priority : 'No priority.';

                # Include the spinning "working" indicator if it's been grabbed.
                if ( $obj && $obj->grabbed_until ) {
                    $html .= ' <img src="' . $app->static_path
                        . 'images/ani-rebuild.gif" width="20" height="20" />'
                }

                return $html;
            },
        },
        worker => {
            base      => '__virtual.single_select',
            label     => 'Worker',
            display   => 'optional',
            order     => 300,
            bulk_html => sub {
                my $prop   = shift;
                my ($objs) = @_;

                # Grab all of the function maps and create a hash for easy
                # lookup against all objects in the ts_job table.
                my @funcmaps = MT->model('ts_funcmap')->load();
                my $func = {};
                foreach my $funcmap (@funcmaps) {
                    $func->{ $funcmap->funcid } = $funcmap->funcname;
                }

                my @out;
                foreach my $obj (@$objs) {
                    my $funcid = $obj && $obj->funcid
                        ? $obj->funcid : 'No worker.';

                    push @out, $func->{ $funcid };
                }
                return @out;
            },
            bulk_sort => sub {
                my $prop   = shift;
                my ($objs) = @_;

                # Create a hash relating the jobid to the worker.
                my $jobid_worker = {};
                foreach my $obj (@$objs) {
                    next unless $obj;

                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or next;

                    my $blog = MT->model('blog')->load( $fi->blog_id )
                        or next;

                    $jobid_worker->{ $obj->jobid } = $blog->name;
                }

                # Use the hash created above to sort by blog name and return the
                # result!
                return sort {
                    my $a_jobid = $a && $a->jobid ? $a->jobid : '';
                    my $b_jobid = $b && $b->jobid ? $b->jobid : '';
                    lc ($jobid_worker->{ $a_jobid })
                         cmp lc($jobid_worker->{ $b_jobid })
                } @$objs;
            },
            single_select_options => sub {
                my @options;
                my $iter = MT->app->model('ts_funcmap')->load_iter();
                while ( my $funcmap = $iter->() ) {
                    push @options, {
                        label => $funcmap->funcname,
                        value => $funcmap->funcid,
                    };
                }
                return \@options;
            },
            terms => sub {
                my $prop = shift;
                my $value = $prop->normalized_value(@_);

                # Filters return the ts_funcmap funcid, and the funcid can be
                # related to ts_job.ts_job_funcid.
                return { 'funcid' => $value };
            },
        },
        blog_name => {
            label        => 'Website/Blog Name',
            filter_label => '__WEBSITE_BLOG_NAME',
            order        => 400,
            display      => 'default',
            site_name    => 1,
            view         => [ 'system', 'website', 'blog' ],
            bulk_html    => sub {
                my $prop   = shift;
                my ($objs) = @_;

                # Grab the blog IDs from the fileinfo record, and use those to
                # build the Website/Blog Name labels.
                my @out;
                foreach my $obj (@$objs) {
                    # Blank, no Website/Blog Name to report.
                    if (!$obj || !$obj->uniqkey) {
                        push @out, '';
                        next;
                    }

                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey );
                    if (!$fi) {
                        push @out, ''; # Blank, no Website/Blog Name to report.
                        next;
                    }

                    my $blog = MT->model('blog')->load( $fi->blog_id );
                    if (!$blog) {
                        push @out, ''; # Blank, no Website/Blog Name to report.
                        next;
                    }

                    my $website = MT->model('website')->load( $blog->parent_id );
                    if (!$website) {
                        push @out, $blog->name; # Only the blog name exists.
                        next;
                    }

                    # Assemble the blog name and website name for the label.
                    push @out, join( '/', $website->name, $blog->name );
                }

                return @out;
            },
            bulk_sort => sub {
                my $prop   = shift;
                my ($objs) = @_;

                # Create a hash relating the jobid to the blog name.
                my $jobid_blog = {};
                foreach my $obj (@$objs) {
                    next unless $obj;

                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or next;

                    my $blog = MT->model('blog')->load( $fi->blog_id )
                        or next;

                    $jobid_blog->{ $obj->jobid } = $blog->name;
                }

                # Use the hash created above to sort by blog name and return the
                # result!
                return sort {
                    my $a_jobid = $a && $a->jobid ? $a->jobid : '';
                    my $b_jobid = $b && $b->jobid ? $b->jobid : '';
                    lc ($jobid_blog->{ $a_jobid })
                         cmp lc($jobid_blog->{ $b_jobid })
                } @$objs;
            },
            filter_editable => 1,
            filter_label => 'Website/Blog Name',
            filter_tmpl => '<mt:Var name="filter_form_single_select">',
            base_type => 'single_select',
            
            single_select_options => sub {
                my @options;
                my $iter = MT->app->model('ts_funcmap')->load_iter();
                while ( my $funcmap = $iter->() ) {
                    push @options, {
                        label => $funcmap->funcname,
                        value => $funcmap->funcid,
                    };
                }
                return \@options;
            },
        },
        template => {
            base    => '__virtual.string',
            label   => 'Template',
            display => 'default',
            order   => 500,
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;

                if (!$obj || !$obj->funcid) {
                    return 'Object funcid not found.';
                }

                if ($obj->funcid == $worker_func->funcid) {
                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or return 'Fileinfo record not found.';

                    my $tmpl = MT->model('template')->load( $fi->template_id )
                        or return 'Template not found.';

                    return $tmpl->name;
                }
                else {
                    # If this isn't a MT::Worker::Publish worker, then just
                    # give up because there is no template associated.
                    my $worker = MT->model('ts_funcmap')->load({
                        funcid => $obj->funcid,
                    });

                    return '*' . $worker->funcname . '*';
                }
            },
            bulk_sort => sub {
                my $prop   = shift;
                my ($objs) = @_;

                # Create a hash relating the jobid to the template name.
                my $jobid_tmplname = {};
                foreach my $obj (@$objs) {
                    next unless $obj;

                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or next;

                    my $tmpl = MT->model('template')->load( $fi->template_id )
                        or next;

                    $jobid_tmplname->{ $obj->jobid } = $tmpl->name;
                }

                # Use the hash created above to sort by template name and return
                # the result!
                return sort {
                    my $a_jobid = $a && $a->jobid ? $a->jobid : '';
                    my $b_jobid = $b && $b->jobid ? $b->jobid : '';
                    lc ($jobid_tmplname->{ $a_jobid })
                         cmp lc($jobid_tmplname->{ $b_jobid })
                } @$objs;
            },
            # Can't be filtered. Well, I think it *could* be if a join were done
            # to the fileinfo table, but I havne't tried that.
            filter_editable => 0,
        },
        file_path => {
            base    => '__virtual.string',
            label   => 'File Path',
            display => 'default',
            order   => 600,
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;

                if (!$obj || !$obj->funcid) {
                    return 'Object funcid not found.';
                }

                if ($obj->funcid == $worker_func->funcid) {
                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or return 'Fileinfo record not found.';

                    return $fi->file_path;
                }
                else {
                    # If this isn't a MT::Worker::Publish worker, then there is
                    # no file path info to return, but we can still return
                    # potentially useful information.
                    return '*Unique key: ' . $obj->uniqkey
                        . ', Coalesce value: ' . $obj->coalesce . '*';
                }
            },
            bulk_sort => sub {
                my $prop   = shift;
                my ($objs) = @_;

                # Create a hash relating the jobid to the file path.
                my $jobid_file = {};
                foreach my $obj (@$objs) {
                    next unless $obj;

                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or next;

                    $jobid_file->{ $obj->jobid } = $fi->file_path;
                }

                # Use the hash created above to sort by file path and return
                # the result!
                return sort {
                    my $a_jobid = $a && $a->jobid ? $a->jobid : '';
                    my $b_jobid = $b && $b->jobid ? $b->jobid : '';
                    lc ($jobid_file->{ $a_jobid })
                         cmp lc($jobid_file->{ $b_jobid })
                } @$objs;
            },
            # Can't be filtered. Well, I think it *could* be if a join were done
            # to the fileinfo table, but I havne't tried that.
            filter_editable => 0,
        },
    };
}

sub menus {
    my $app = MT->instance;

    # Find the MT::Worker::Publisher funcid, which is used to figure out how
    # many job there are. This is used in the MT5 menu options below.
    my $funcmap = $app->model('ts_funcmap')->load({
        funcname => 'MT::Worker::Publish',
    });

    # Are there *only* non-publishing workers? Use them to determine if the
    # `mode` and `args` keys should be included, which is how the menu
    # highlight is added.
    my $only_non_publish_workers = 0;
    if (
        $app->model('ts_job')->exist(
            { funcid => { not => $funcmap->funcid }, },
        )
        && !$app->model('ts_job')->exist(
            { funcid => $funcmap->funcid },
        )
    ) {
        $only_non_publish_workers = 1;
    }

    return {
        # MT5
        'pq_monitor' => {
            label => pq_monitor_menu_label($app, $funcmap),
            order => 1000,
            mode  => 'list',
            args  => {
                '_type'   => 'ts_job',
                'blog_id' => '0', # Always blog ID 0, system.
            },
            permission => 'administer',
            condition  => sub {
                return 1 if MT->product_version !~ /^4/; # MT5 only
                return 0;
            },
        },
        # We must add the `mode` and `args` keys to the menu sub-item to make
        # the menu functional.
        # The `status` item is added just in case there are no other jobs in
        # the PQ, forcing the menu to show.
        'pq_monitor:status' => {
            label => 'No jobs in the Publish Queue',
            order => 1,
            view  => [ "system", "blog", "website" ],
            mode  => 'list',
            args  => {
                '_type'   => 'ts_job',
                'blog_id' => '0', # Always blog ID 0, system.
            },
            permission => 'administer',
            condition  => sub {
                # Only display if there are *no* jobs in the PQ.
                my $result = $app->model('ts_job')->exist();
                return 0 if $result; # There are jobs, so hide.
                return 1;            # There are no jobs, so display.
            },
        },
        # "Newest publish job: inserted 5 minutes ago"
        'pq_monitor:newest' => {
            label => pq_monitor_age_menu_label($app, $funcmap, 'descend'),
            order => 10,
            view  => [ "system", "blog", "website" ],
            mode  => 'list',
            args  => {
                '_type'   => 'ts_job',
                'blog_id' => '0', # Always blog ID 0, system.
            },
            permission => 'administer',
            condition  => sub {
                return $app->model('ts_job')->exist(
                    { funcid => $funcmap->funcid, },
                ) || 0;
            },
        },
        # "Oldest publish job: inserted 40 minutes ago"
        'pq_monitor:oldest' => {
            label      => pq_monitor_age_menu_label($app, $funcmap, 'ascend'),
            order      => 11,
            condition  => sub {
                return $app->model('ts_job')->exist(
                    { funcid => $funcmap->funcid, },
                ) || 0;
            },
        },
        # "2 non-publisher jobs: Bob Rebuilder, Reblog Import"
        'pq_monitor:other' => {
            label => pq_monitor_other_jobs_menu_label($app, $funcmap),
            order => 20,
            view  => [ "system", "blog", "website" ],
            mode  => ($only_non_publish_workers ? 'list' : ''),
            args  => {
                '_type'   => 'ts_job',
                'blog_id' => '0', # Always blog ID 0, system.
            },
            permission => 'administer',
            condition  => sub {
                return $app->model('ts_job')->exist(
                    { funcid => { not => $funcmap->funcid }, },
                ) || 0;
            },
        },
        'pq_monitor:errors' => {
            label => 'Error Log',
            order => 30,
            view  => [ "system", "blog", "website" ],
            mode  => 'list',
            args  => {
                '_type'   => 'ts_error',
                'blog_id' => '0', # Always blog ID 0, system.
            },
            permission => 'administer',
            condition  => sub {
                return $app->model('ts_error')->exist() || 0;
            },
        },
        # MT4
        'manage:pqueue' => {
            label      => 'Publish Queue Jobs',
            order      => 1000,
            mode       => 'PQManager.list',
            view       => 'system',
            permission => 'administer',
            condition  => sub {
                return 1 if MT->product_version =~ /^4/; # MT4 only
                return 0;
            },
        },
        'system:pqueue' => {
            label      => 'Publish Queue Jobs',
            order      => 1000,
            mode       => 'PQManager.list',
            view       => 'system',
            permission => 'administer',
            condition  => sub {
                return 1 if MT->product_version =~ /^4/; # MT4 only
                return 0;
            },
        },
    };
}

# MT5+ surfaces a top-level menu to deliver status information about what is in
# the Publish Queue. It also gets a special label that includes the job count.
sub pq_monitor_menu_label {
    my ($app)     = shift;
    my ($funcmap) = shift;

    # Count the number of publishing jobs in the queue, to be displayed in an
    # orange-yellow dot next to the menu label. The obvious way to do this is
    # to count all rows where `funcid` matches the Publish Worker:
    #     my $count = $app->model('ts_job')->count({
    #         funcid => $funcmap->funcid,
    #     });
    # However, this gets cached and so is often wrong. So instead, get all
    # `ts_job` records and subtract out the non-Publish Worker rows, and now we
    # have a good total!
    my $count = $app->model('ts_job')->count();
    my $non_pq_count = $app->model('ts_job')->count({
        funcid => { not => $funcmap->funcid },
    });
    $count -= $non_pq_count;

    return <<LABEL;
<span title="There are currently $count items in the Publish Queue.">
    PQ Jobs
    <span class="pq-count">$count</span>
</span>
<style type="text/css">
    .pq-count {
        position: absolute;
        right: 25px;
        top: 4px;
        display: block;
        background: #f8b500;
        color: #fff;
        text-align: center;
        min-width: 12px;
        float: right;
        -webkit-border-radius: 10px;
        -moz-border-radius: 10px;
        border-radius: 10px;
        padding: 0px 3px 2px;
        font-weight: normal;
    }
</style>
LABEL
}

# The newest/oldest publishing job was added to the queue x minutes ago.
sub pq_monitor_age_menu_label {
    my ($app)     = shift;
    my ($funcmap) = shift;
    my ($order)   = shift;

    my $job = $app->model('ts_job')->load(
        {
            funcid => $funcmap->funcid,
        },
        {
            sort      => 'insert_time',
            direction => $order,
            limit     => 1,
        }
    );
    my $insert_time = $job
        ? $job->insert_time
        : return "Couldn't load insert time?";

    my $ts            = epoch2ts(undef, $insert_time);
    my $date_format   = MT::App::CMS::LISTING_DATE_FORMAT();
    my $relative_time = relative_date( $ts, time, undef );

    my $age_label = $order eq 'descend' ? 'Newest' : 'Oldest';

    return "$age_label publish job: inserted $relative_time";
}

# Show non-publisher jobs, too, such as Reblog and Bob the Rebuilder.
sub pq_monitor_other_jobs_menu_label {
    my ($app)     = shift;
    my ($funcmap) = shift;

    my $additional_jobs = $app->model('ts_job')->count({
        funcid => { not => $funcmap->funcid },
    }) || '0';

    my @all_workers = $app->model('ts_funcmap')->load(
        {
            funcid => { not => $funcmap->funcid },
        },
    );
    my @workers;
    foreach my $worker (@all_workers) {
        # Check to see if this worker has anything in the queue. If it does,
        # note it.
        if ( $app->model('ts_job')->exist({ funcid => $worker->funcid }) ) {
            my $funcname = $worker->funcname;
            # Strip the "::Worker::" out of the name simply to help conserve
            # space.
            $funcname =~ s/::Worker::/ /;
            push @workers, '&bull; '.$funcname;
        }
    }

    my $plural = scalar @workers == 1 ? '' : 's';

    return "$additional_jobs non-publisher job$plural:<br />"
        . join("<br />", @workers);
}

# This plugin updates the Listing Framework date filters to include an "is
# older than" option, which requires an update to the JS function `dateOption`,
# in the template list_common.tmpl. This callback updates `dateOption` to make
# the "days" field appear for the date field type.
sub xfrm_list_common {
    my ( $cb, $app, $tmpl ) = @_;
    # Give up if not on the PQ Manager listing screen.
    return unless $app->mode eq 'list' && $app->param('_type') eq 'ts_job';

    my $html = "case 'days_older':\ncase 'days':";
    $$tmpl =~ s{case 'days':}{$html};
}

# Show the rebuild warning on the popup dialog.
sub xfrm_rebuild_confirm {
    my ($cb, $app, $param, $tmpl) = @_;
    my $plugin = $app->component('pqmanager');
    my $config = $plugin->get_config_hash('system');

    # Move any previously-selected blog IDs into an array.
    my @warning_blog_ids;
    if ( ref $config->{republish_warning_blog_ids} eq 'ARRAY' ) {
        (@warning_blog_ids) = @{$config->{republish_warning_blog_ids}};
    }
    else {
        push @warning_blog_ids, $config->{republish_warning_blog_ids};
    }

    # Blogs/websites are always republished at the blog/website level, so we can
    # assume that the $app->blog context is always available... right? Test just
    # to be sure.
    my $current_blog_id = $app->blog ? $app->blog->id : return 1;

    # Give up if the current blog wasn't selected to display the warning
    # message.
    return 1
        unless grep( defined $_ && m/^$current_blog_id$/,
                                        @warning_blog_ids );

    # Find the submission form.
    my $old = q{<mt:include name="include/chromeless_header.tmpl">};

    # The message to display. This may contain HTML or even MT tags, but nothing
    # special has to be done because the template isn't rendered yet.
    my $message = $config->{republish_warning_message};

    # Create an Insert Video icon for the toolbar
    my $new = <<HTML;
<div id="msg-block">
    <div class="msg msg-error">
        <p class="msg-text">
            $message
        </p>
    </div>
</div>
HTML

    # Grab the template itself, which we'll use to update the links. Then push
    # the updated template back into the context. All done!
    my $tmpl_text = $tmpl->text;
    $tmpl_text =~ s/$old/$old$new/;
    $tmpl->text( $tmpl_text );

    1; # Transformer callbacks should always return true.
}

# The `post_build` callback is run at the end of a publish job. Use it to log
# big republish activity.
sub callback_post_build {
    my $app = MT->instance;
    my $q   = $app->param();

    # If there's an entry ID, then that means this is an entry being
    # republished. Don't record that.
    return if $app->mode ne 'rebuild';
    return if $q->param('entry_id');

    my $start_time = epoch2ts( $app->blog, $q->param('start_time') );
    $start_time    = ts2iso( $app->blog, $start_time );
    my $end_time   = epoch2ts( $app->blog, time );
    $end_time      = ts2iso( $app->blog, $end_time );

    my $blog_id    = $q->param('blog_id');
    my $type       = $q->param('type');
    $type =~ s/%2C/, /g;

    $app->log({
        level    => MT->model('log')->INFO(),
        category => 'publish',
        class    => 'pqmanager',
        blog_id  => $blog_id,
        author   => $app->user->id,
        message  => "This blog was republished at start time $start_time and "
            . "completed at $end_time, and republished the archive types $type.",
    });
}

1;

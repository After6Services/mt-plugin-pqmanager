# Publish Queue Manager Plugin for Movable Type
# Author: Byrne Reese, byrne at majordojo dot com
# Copyright (C) 2008 Six Apart, Ltd.
package PQManager::Plugin;

use strict;
use MT::Util qw( relative_date epoch2ts iso2ts );
use warnings;
use Carp;

use MT::TheSchwartz;
use MT::TheSchwartz::Error;

# A feature of Melody Maker.
sub status_job_queue {
    my $app = shift;
    my ($ctx) = @_;
    my $blog = $app->can('blog') ? $app->blog : $ctx->stash('blog');
    return MT->model('ts_job')->count();
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

# The listing screen (for MT4 only).
sub mode_list_queue {
    my $app = shift;
    my %param = @_;
    my $q = $app->can('query') ? $app->query : $app->param;

    # Redirect to the blog dashboard if a blog_id is specified, since the PQ
    # doesn't work on a blog-specific basis.
    if (my $blog = $app->blog) {
        $app->redirect(
            $app->uri(
                'mode' => 'dashboard',
                args   => {
                    blog_id => $blog->id,
                }
            )
        );
    }

    # This anonymous subroutine will process each row of data returned
    # by the database and map that data into a set of columns that will
    # be displayed in the table itself. The method takes as input:
    #   * the object associated with the current row
    #   * an empty hash for the row that should be populated with content
    #     from the $obj passed to it.
    require MT::FileInfo;
    require MT::Template;
    require MT::Blog;
    require MT::TheSchwartz::Error;
    my %blogs;
    my %tmpls;
    my $code = sub {
        my ($job, $row) = @_;

        $row->{'insert_time_raw'} = $job->insert_time;
        my $fi  = MT::FileInfo->load({ id => $job->uniqkey });
        my $err = MT::TheSchwartz::Error->load({ jobid => $job->jobid });

        $tmpls{$fi->template_id} ||= MT::Template->load({ id => $fi->template_id });
        my $tmpl                   = $tmpls{$fi->template_id};

        if ($tmpl) {
            my $blog = $blogs{$tmpl->blog_id}  
                   ||= MT::Blog->load({ id => $tmpl->blog_id });
            $row->{'blog'}     = $blog->name;
            $row->{'template'} = $tmpl->name;
            $row->{'path'}     = $fi->file_path;
        } else {
            $row->{'blog'}            = '<em>Deleted</em>';
            $row->{'template'}        = '<em>Deleted</em>';
            $row->{'path'}            = '<em>Deleted</em>';
        }
        my $ts                    = epoch2ts(undef, $job->insert_time);
        $row->{'id'}              = $job->jobid;
        $row->{'priority'}        = $job->priority;
        $row->{'claimed'}         = $job->grabbed_until ? 1 : 0;
        $row->{'insert_time'}     = relative_date( $ts, time );
        $row->{'insert_time_ts'}  = $ts;
        $row->{'has_error'}       = $err ? 1 : 0;
        $row->{'error_msg'}       = $err ? $err->message : undef;
    };

    require MT::TheSchwartz::FuncMap;
    my $fm = MT::TheSchwartz::FuncMap->load(
        {funcname => 'MT::Worker::Publish'});

    my (%terms, %args, $params);

    # If $fm is empty, that means there are no templates set to publish 
    # through the Publish Queue, so display a message to the user about 
    # this.
    if (!$fm) {
        $params = {
            'no_pq' => 1,
        };
    }
    
    # Publish Queue is being used--load any jobs and show them to the user.
    else {
        # %terms is used in case you want to filter the query that will fetch
        # the items from the database that correspond to the rows of the table
        # being rendered to the screen
        %terms = ( funcid => $fm->funcid );

        # %args is used in case you want to sort or otherwise modify the 
        # query arguments of the table, e.g. the sort order or direction of
        # the query associated with the data being displayed in the table.
        my $clause = ' = ts_job_uniqkey';
        %args = (
            sort  => [
                       { column => "priority", desc => "DESC" },
                       { column => "insert_time", }
                   ],
            direction => 'descend',
            join => MT::FileInfo->join_on( undef, { id => \$clause }),
        );

        # %params is an addition hash of input parameters into the template
        # and can be used to hold an arbitrary set of name/value pairs that
        # can be displayed in your template.
        $params = {
            'is_deleted'  => $q->param('deleted')  ? 1 : 0,
            'is_priority' => $q->param('priority') ? 1 : 0,
            ($q->param('priority') ? ('priority' => $q->param('priority')) : ())
        };
    }

    # Fetch an instance of the current plugin using the plugin's key.
    # This is done as a convenience only.
    my $plugin = MT->component('PQManager');

    # This is the main work horse of your handler. This subrotine will
    # actually conduct the query to the database for you, populate all
    # that is necessary for the pagination controls and more. The 
    # query is filtered and controlled using the %terms and %args 
    # parameters, with 'type' corresponding to the database table you
    # will query.
    return $app->listing({
        type           => 'ts_job', # the object's MT->model
        terms          => \%terms,
        args           => \%args,
        listing_screen => 1,
        code           => $code,
        template       => $plugin->load_tmpl('list.tmpl'),
        params         => $params,
    });
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
        },
        insert_time => {
            base    => '__virtual.date',
            label   => 'Insert Date',
            display => 'default',
            col     => 'insert_time',
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                my $insert_time = $prop->raw(@_) or return '';
                my $ts          = epoch2ts(undef, $insert_time);
                my $date_format = MT::App::CMS::LISTING_DATE_FORMAT();
                my $is_relative
                    = ( $app->user->date_format || 'relative' ) eq
                    'relative' ? 1 : 0;
                return $is_relative
                    ? MT::Util::relative_date( $ts, time, undef )
                    : MT::Util::format_ts(
                        $date_format,
                        $ts,
                        undef,
                        $app->user ? $app->user->preferred_language
                        : undef
                    );
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
                my $html = $obj->priority;
                
                # Include the spinning "working" indicator if it's been grabbed.
                if ( $obj->grabbed_until ) {
                    $html .= ' <img src="' . $app->static_path
                        . 'images/ani-rebuild.gif" width="20" height="20" />'
                }

                return $html;
            },
        },
        worker => {
            base      => '__virtual.string',
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
                    push @out, $func->{ $obj->funcid };
                }
                return @out;
            },
            bulk_sort => sub {
                my $prop   = shift;
                my ($objs) = @_;

                # Create a hash relating the jobid to the blog name.
                my $jobid_blog = {};
                foreach my $obj (@$objs) {
                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or next;

                    my $blog = MT->model('blog')->load( $fi->blog_id )
                        or next;

                    $jobid_blog->{ $obj->jobid } = $blog->name;
                }

                # Use the hash created above to sort by blog name and return the
                # result!
                return sort {
                    lc( $jobid_blog->{ $a->jobid } )
                        cmp lc( $jobid_blog->{ $b->jobid } )
                } @$objs;
            },
            # Can't be filtered. Well, I think it *could* be if a join were done
            # to the fileinfo table, but I havne't tried that.
            filter_editable => 0,
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
                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or next;

                    my $blog = MT->model('blog')->load( $fi->blog_id )
                        or next;

                    $jobid_blog->{ $obj->jobid } = $blog->name;
                }

                # Use the hash created above to sort by blog name and return the
                # result!
                return sort {
                    lc( $jobid_blog->{ $a->jobid } )
                         cmp lc( $jobid_blog->{ $b->jobid } )
                } @$objs;
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

                if ($obj->funcid == $worker_func->funcid) {
                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or return 'fileinfo record not found';

                    my $tmpl = MT->model('template')->load( $fi->template_id )
                        or return 'template not found';

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
                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or next;

                    my $tmpl = MT->model('template')->load( $fi->template_id )
                        or next;

                    $jobid_tmplname->{ $obj->jobid } = $tmpl->name;
                }

                # Use the hash created above to sort by template name and return
                # the result!
                return sort {
                    lc( $jobid_tmplname->{ $a->jobid } )
                        cmp lc( $jobid_tmplname->{ $b->jobid } )
                } @$objs;
            },
            # Can't be filtered. Well, I think it *could* be if a join were done
            # to the fileinfo table, but I havne't tried that.
            filter_editable => 0,
        },
        file_path => {
            base    => '__virtual.string',
            label   => 'File Path',
            display => 'force',
            order   => 600,
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;

                if ($obj->funcid == $worker_func->funcid) {
                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or return 'fileinfo record not found';

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
                    my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                        or next;

                    $jobid_file->{ $obj->jobid } = $fi->file_path;
                }

                # Use the hash created above to sort by file path and return
                # the result!
                return sort {
                    lc( $jobid_file->{ $a->jobid } )
                        cmp lc( $jobid_file->{ $b->jobid } )
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

    my $count = $app->model('ts_job')->count({
        funcid => $funcmap->funcid,
    });

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
    my $insert_time = $job ? $job->insert_time : '';

    my $ts          = epoch2ts(undef, $insert_time);
    my $date_format = MT::App::CMS::LISTING_DATE_FORMAT();
    my $is_relative
        = ( $app->user->date_format || 'relative' ) eq
        'relative' ? 1 : 0;
    my $relative_time = $is_relative
        ? MT::Util::relative_date( $ts, time, undef )
        : MT::Util::format_ts(
            $date_format,
            $ts,
            undef,
            $app->user ? $app->user->preferred_language
            : undef
        );

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

1;

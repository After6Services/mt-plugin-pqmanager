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

    my @jobs = $app->param('id');
    for my $job_id (@jobs) {
        my $job = MT->model('ts_job')->load({jobid => $job_id})
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
        return $app->error("You must enter a number between 1 and 10.");
    }

    my @jobs = $q->param('id');
    for my $job_id (@jobs) {
        my $job = MT->model('ts_job')->load({jobid => $job_id})
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
            display => 'force',
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

                # Use the has created above to sort by blog name and return the
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
            view         => [ 'system', 'website' ],
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

                # Use the has created above to sort by blog name and return the
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
                # If this isn't a MT::Worker::Publish worker, then just give up
                # because there is no template associated.
                return '' if $obj->funcid != $worker_func->funcid;

                my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                    or return 'fileinfo record not found';

                my $tmpl = MT->model('template')->load( $fi->template_id )
                    or return 'template not found';
                return $tmpl->name;
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

                # Use the has created above to sort by template name and return
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
                # If this isn't a MT::Worker::Publish worker, then just give up
                # because there is no template associated.
                return '' if $obj->funcid != $worker_func->funcid;

                my $fi  = MT->model('fileinfo')->load( $obj->uniqkey )
                    or return 'fileinfo record not found';

                return $fi->file_path;
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

                # Use the has created above to sort by file path and return
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

# The following two functions work together to decide how menus are shown in MT.
sub mt5_menu_condition {
    # This is MT5.x; display the Tools > Publish Queue menu item.
    return 1 if MT->product_version =~ /^5/;
    # This is MT4 or something else; don't display Tools > Publish Queue
    # because it exists at Manage > Publish Queue.
    return 0;
}
sub mt4_menu_condition {
    # This is MT4.x; display the Manage > Publish Queue menu item.
    return 1 if MT->product_version =~ /^4/;
    # This is MT5 or something else; don't display Manage > Publish Queue
    # because it exists at Tools > Publish Queue.
    return 0;
}

1;

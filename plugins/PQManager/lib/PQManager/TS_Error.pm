package PQManager::TS_Error;

use strict;
use warnings;
use MT::Util qw( relative_date format_ts epoch2ts ts2epoch iso2ts decode_js );

sub list_properties {
    return {
        funcid => {
            base      => '__virtual.single_select',
            label     => 'Worker',
            display   => 'default',
            order     => 100,
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
        jobid => {
            base    => '__virtual.integer',
            label   => 'Job ID',
            order   => 200,
            display => 'optional',
            col     => 'jobid',
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                return $obj && $obj->jobid ? $obj->jobid : 'No jobid found.';
            },
        },
        message => {
            base => '__virtual.string',
            label => 'Message',
            order => 300,
            display => 'force',
            col => 'message',
            html => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                return $obj ? $obj->message : '';
            },
        },
        error_time => {
            base    => '__virtual.date',
            label   => 'Error Date',
            display => 'default',
            order   => 400,
            col     => 'error_time',
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;

                # Error time is stored as epoch, not a time stamp, so it needs
                # to be converted.
                my $error_time  = $obj ? $obj->error_time : return '';
                my $ts          = epoch2ts(undef, $error_time);
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
                    $a->error_time <=> $b->error_time;
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
    };
}

# The "delete" button on the listing screen.
sub mode_delete {
    my $app = shift;
    $app->validate_magic or return;
    my $q = $app->can('query') ? $app->query : $app->param;

    # Grab the Jobs that have been selected.
    my @errors = $q->param('id');

    # If "select all xxx items" was chosen, select them all.
    if ( $q->param('all_selected') ) {
        my $iter = $app->model('ts_error')->load_iter();
        while ( my $error = $iter->() ) {
            push @errors, $error->jobid;
        }
    }

    for my $job_id (@errors) {
        my $error = $app->model('ts_error')->load({jobid => $job_id})
            or next;
        $error->remove or die $error->errstr;
    }

    # Check if there are any items left in the ts_error table. If not, redirect
    # back to the Manage Publish Queue Jobs screen.
    if ( $app->model('ts_error')->exist() ) {
        $app->add_return_arg( saved_deleted => 1 );
        $app->call_return;
    }
    else {
        # No errors; go back to the PQ jobs listing.
        $app->redirect(
            $app->uri(
                mode => 'list',
                args => {
                    '_type'   => 'ts_job',
                    'blog_id' => 0,
                },
            )
        );
    }
}

1;

__END__

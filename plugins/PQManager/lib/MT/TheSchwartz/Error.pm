# This is basically the same as the "standard" MT::TheSchwartz::Error package
# that comes with MT, except that it includes the `primary_key` field in
# `install_properties`, which is required for the listing framework and for MT
# to directly interact with the table.
package MT::TheSchwartz::Error;

use strict;
use base qw( MT::Object );

__PACKAGE__->install_properties(
    {   column_defs => {
            jobid  => 'integer not null',    # bigint unsigned not null
            funcid => 'integer not null',    # int unsigned not null default 0
            # 255 characters isn't enough to capture the length of an error
            # that may occur. Bump this to `text` and the problem can be
            # avoided. Also, note the schema bump in config.yaml.
            #message    => 'string(255) not null',  # varchar(255) not null
            message => 'text',
            error_time => 'integer not null',      # integer unsigned not null
        },
        datasource => 'ts_error',
        indexes    => {
            jobid       => 1,
            error_time  => 1,
            funcid_time => { columns => [ 'funcid', 'error_time' ], },
            clustered =>
                { columns => [ 'jobid', 'funcid' ], ms_clustered => 1, },
        },
        defaults  => { funcid => 0, },
        cacheable => 0,
        # Add the primary key, which is necessary for the Listing Framework to
        # display this table's contents.
        primary_key => 'jobid',
    }
);

sub class_label {
    MT->translate("Job Error");
}

1;

__END__

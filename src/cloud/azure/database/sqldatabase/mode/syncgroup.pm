#
# Copyright 2024 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package cloud::azure::database::sqldatabase::mode::syncgroup;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use centreon::plugins::templates::catalog_functions qw(catalog_status_threshold);

use DateTime::Format::ISO8601;

sub custom_calc {
    my ($self, %options) = @_;
    $self->{result_values}->{syncState} = $options{new_datas}->{$self->{instance} . '_syncState'};
    $self->{result_values}->{lastSync} = $options{new_datas}->{$self->{instance} . '_lastSync'};
    return 0;
}

sub custom_output {
    my ($self, %options) = @_;
    
    my $syncState = $self->{result_values}->{syncState};
    my $lastSync = $self->{result_values}->{lastSync};

    $lastSync = DateTime::Format::ISO8601->parse_datetime($lastSync);
    $lastSync = $lastSync->set_time_zone('Europe/Paris');
    $lastSync = $lastSync->strftime('%d/%m/%Y %H:%M:%S');

    return sprintf("Sync State: '%s', Last Sync: '%s'",
        $syncState,
        $lastSync
    );

}

sub set_counters {
    my ($self, %options) = @_;
    
    $self->{maps_counters_type} = [
        { name => 'health', type => 0 },
    ];

    $self->{maps_counters}->{health} = [
        { label => 'status', threshold => 0, set => {
                key_values => [ { name => 'syncState' }, { name => 'lastSync' } ],
                closure_custom_calc => $self->can('custom_calc'),
                closure_custom_output => $self->can('custom_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => \&catalog_status_threshold,
            }
        },
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $options{options}->add_options(arguments => {
        "api-version:s"         => { name => 'api_version', default => '2018-01-01'},
        "resource:s"            => { name => 'resource' },
        "sync-group:s"          => { name => 'sync_group' },
        "warning-status:s"      => { name => 'warning_status'},
        "critical-status:s"     => { name => 'critical_status', default => '%{syncState} =~ /^Error$/ || %{syncState} =~ /^Warning$/' },
        "unknown-status:s"      => { name => 'unknown_status', default => '' },
        "ok-status:s"           => { name => 'ok_status', default => '%{syncState} =~ /^Good$/ || %{syncState} =~ /^Progressing$/' },
    });
    
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    if (!defined($self->{option_results}->{resource})) {
        $self->{output}->add_option_msg(short_msg => "Need to specify either --resource <name> with --resource-group, --resource-type and --resource-namespace options or --resource <id>.");
        $self->{output}->option_exit();
    }

    $self->{api_version} = (defined($self->{option_results}->{api_version}) && $self->{option_results}->{api_version} ne "") ? $self->{option_results}->{api_version} : 2018-01-01;
    
    $self->{az_resource} = $self->{option_results}->{resource};
    $self->{az_sync_group} = $self->{option_results}->{sync_group};
    
    if ($self->{az_resource} =~ /^\/subscriptions\/(.*)\/resourceGroups\/(.*)\/providers\/Microsoft\.Sql\/servers\/(.*)\/databases\/(.*)$/) {
        $self->{az_subscription} = $1;
        $self->{az_resource_group} = $2;
        $self->{az_servers} = $3;
        $self->{az_databases} = $4;
    }

    print STDERR "$self->{az_resource}\n";

    $self->change_macros(macros => ['warning_status', 'critical_status', 'unknown_status', 'ok_status']);
}

sub manage_selection {
    my ($self, %options) = @_;

    my $status = $options{custom}->azure_get_syncgroup(
        resource => $self->{az_resource},
        subscription => $self->{az_subscription},
        resource_group => $self->{az_resource_group},
        servers => $self->{az_servers},
        databases => $self->{az_databases},
        sync_group => $self->{az_sync_group},
        api_version => '2021-11-01'
    );

    $self->{health} = {
        syncState => $status->{properties}->{syncState},
        lastSync => $status->{properties}->{lastSyncTime}
    };
}

1;

__END__

=head1 MODE

Check resource health status. Useful to determine host status (ie UP/DOWN).

=over 8

=item B<--resource>

Set resource name or ID (required).

=item B<--resource-group>

Set resource group (required if resource's name is used).

=item B<--resource-namespace>

Set resource namespace (required if resource's name is used).

=item B<--resource-type>

Set resource type (required if resource's name is used).

=back

=cut

package Server::Router;

use Server::Alias;
use Server::AppendGame;
use Server::Chat;
use Server::EditGame;
use Server::EditGame;
use Server::JoinGame;
use Server::ListGames;
use Server::Login;
use Server::Logout;
use Server::Map;
use Server::NewGame;
use Server::PasswordReset;
use Server::Plan;
use Server::Register;
use Server::Results;
use Server::SaveGame;
use Server::Settings;
use Server::Template;
use Server::UserInfo;
use Server::ViewGame;

use CGI::PSGI;
use JSON;
use POSIX;
use Util::Watchdog;

my %paths = (
    # Operations on single games. To be renamed
    '/append-game/' => sub {
        Server::AppendGame->new()
    },
    '/edit-game/' => sub {
        Server::EditGame->new({ mode => 'content' })
    },
    '/set-game-status/' => sub {
        Server::EditGame->new({ mode => 'status' })
    },
    '/view-game/' => sub {
        Server::ViewGame->new()
    },
    '/join-game/' => sub {
        Server::JoinGame->new()
    },
    '/new-game/' => sub {
        Server::NewGame->new()
    },
    '/save-game/' => sub {
        Server::SaveGame->new()
    },
    '/chat/' => sub {
        Server::Chat->new()
    },
    '/plan/' => sub {
        Server::Plan->new()
    },

    '/list-games/' => sub {
        Server::ListGames->new( mode => '')
    },

    # Map editor
    '/map/preview/' => sub {
        Server::Map->new({ mode => 'preview' })
    },
    '/map/save/' => sub {
        Server::Map->new({ mode => 'save' })
    },
    '/map/view/' => sub {
        Server::Map->new({ mode => 'view' })
    },

    # Account management
    '/alias/request/' => sub {
        Server::Alias->new({ mode => 'request' })
    },
    '/alias/validate/' => sub {
        Server::Alias->new({ mode => 'validate' })
    },
    '/login/' => sub {
        Server::Login->new()
    },
    '/logout/' => sub {
        Server::Logout->new()
    },
    '/register/request/' => sub {
        Server::Register->new({ mode => 'request' })
    },
    '/register/validate/' => sub {
        Server::Register->new({ mode => 'validate' })
    },
    '/reset/request/' => sub {
        Server::PasswordReset->new({ mode => 'request' })
    },
    '/reset/validate/' => sub {
        Server::PasswordReset->new({ mode => 'validate' })
    },
    '/settings/' => sub {
        Server::Settings->new()
    },

    # User information
    '/user/metadata/' => sub {
        Server::UserInfo->new({mode => 'metadata'})
    },
    '/user/opponents/' => sub {
        Server::UserInfo->new({mode => 'opponents'})
    },
    '/user/stats/' => sub {
        Server::UserInfo->new({mode => 'stats'})
    },

    # Content rendering
    '/template/' => sub {
        Server::Template->new()
    },

    # External APIs
    '/results/' => sub {
        Server::Results->new()
    },
    '/list-games/by-pattern/' => sub {
        Server::ListGames->new( mode => 'by-pattern')
    },
);

sub route {
    my $env = shift;
    my $q = CGI::PSGI->new($env);

    local *CGI::PSGI::param_or_die = sub {
        my ($q, $param) = @_;
        $q->param($param) // die "Required parameter '$param' undefined\n";
    };

    my $path_info = $q->path_info();
    my $ret;

    eval {
        my $handler = undef;
        my $suffix = '';
        my @components = split m{/}, $path_info;
        for my $i (reverse 0..$#components) {
            my $prefix = join '/', @components[0..$i];
            $prefix .= '/';
            $handler = $paths{$prefix};
            if ($handler) {
                $suffix = substr $path_info, length $prefix;
                last;
            }
        }
        if ($handler) {
            my $app = $handler->();
            with_watchdog 15, sub {
                $app->handle($q, $suffix);
                $ret = $app->output_psgi();
            };
        } else {
            die "Unknown module '$path_info'";
        }
    }; if ($@) {
        my $error = $@;
        chomp $error;

        my $timestamp = asctime localtime;
        chomp $timestamp;

        my $ip = $q->remote_host();
        my $username = $q->cookie('session-username') // '<none>';
        my $params = eval {
            my @vars = grep { !/password/ } $q->param;
            my %params = map { ($_ => $q->param($_)) } @vars;
            encode_json \%params
        };

        print STDERR "[$timestamp] ip=$ip path=$path_info username=$username\nparams=$params\nERROR: $error\n", '-'x60, "\n";
        $ret = [500,
                ["Content-Type", "application/json"],
                [encode_json { error => [ $@ ] }]];
    }

    $ret;
};

sub psgi_router {
    route(@_);
}

1;

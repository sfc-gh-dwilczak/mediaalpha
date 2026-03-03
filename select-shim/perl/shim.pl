use strict;
use warnings;
use Mojolicious::Lite -signatures;
use DBI;
use POSIX qw(strftime);

my $days   = $ENV{ROUTE_DAYS} || 365;
my $cutoff = strftime("%Y-%m-%d", localtime(time() - $days * 86400));

app->log->info("Cutoff date: $cutoff");

my $core = db_connect($ENV{CORE_DSN}, $ENV{CORE_USER}, $ENV{CORE_PASS}, 30);
my $sf   = DBI->connect(
    "dbi:ODBC:$ENV{SF_DSN}",
    $ENV{SF_USER},
    $ENV{SF_PASS},
    { RaiseError => 1, AutoCommit => 1 }
);

sub db_connect {
    my ($dsn, $user, $pass, $retries) = @_;
    for my $i (1 .. $retries) {
        my $dbh = eval {
            DBI->connect($dsn, $user, $pass, { RaiseError => 1, AutoCommit => 1 });
        };
        return $dbh if $dbh;
        print "Waiting for database ($i/$retries)...\n";
        sleep 2;
    }
    die "Could not connect to $dsn after $retries attempts\n";
}

sub run_query {
    my ($dbh, $q) = @_;
    my $sth = $dbh->prepare($q);
    $sth->execute();
    my @cols = @{$sth->{NAME}};
    my @rows;
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, { map { $_ => $row->{$_} } @cols };
    }
    return (\@cols, \@rows);
}

get '/' => sub ($c) {
    $c->stash(
        cutoff  => $cutoff,
        route   => '',
        sql     => '',
        cols    => [],
        rows    => [],
        error   => '',
    );
    $c->render(template => 'index');
};

post '/query' => sub ($c) {
    my $sql = $c->param('sql') // '';
    $sql =~ s/;\s*$//;

    my ($route, $error, @cols, @rows);

    if ($sql !~ /^\s*select/i) {
        $error = "Only SELECT statements are supported.";
    }
    elsif ($sql !~ /created_at\s+between\s+'(\d{4}-\d{2}-\d{2})'\s+and\s+'(\d{4}-\d{2}-\d{2})'/i) {
        $error = "Query must contain: created_at BETWEEN 'YYYY-MM-DD' AND 'YYYY-MM-DD'";
    }
    else {
        my ($start, $end) = ($1, $2);

        my ($dbh, $cols_ref, $rows_ref);
        if ($start ge $cutoff) {
            $route = "CORE (MySQL)";
            $dbh = $core;
        }
        else {
            $route = "ARCHIVE (Snowflake)";
            $dbh = $sf;
        }

        eval {
            ($cols_ref, $rows_ref) = run_query($dbh, $sql);
            @cols = @$cols_ref;
            @rows = @$rows_ref;
        };
        $error = $@ if $@;
    }

    $c->stash(
        cutoff => $cutoff,
        route  => $route // '',
        sql    => $sql,
        cols   => \@cols,
        rows   => \@rows,
        error  => $error // '',
    );
    $c->render(template => 'index');
};

app->start('daemon', '-l', 'http://*:3000');

__DATA__

@@ index.html.ep
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SELECT Routing Shim</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #0f172a;
      color: #e2e8f0;
      min-height: 100vh;
      padding: 2rem;
    }
    .container { max-width: 900px; margin: 0 auto; }
    h1 {
      font-size: 1.75rem;
      font-weight: 700;
      margin-bottom: 0.25rem;
    }
    .subtitle {
      color: #94a3b8;
      font-size: 0.9rem;
      margin-bottom: 2rem;
    }
    .cutoff-badge {
      display: inline-block;
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 6px;
      padding: 0.5rem 1rem;
      font-size: 0.85rem;
      margin-bottom: 1.5rem;
      color: #94a3b8;
    }
    .cutoff-badge strong { color: #38bdf8; }
    textarea {
      width: 100%;
      height: 140px;
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 8px;
      color: #e2e8f0;
      font-family: 'SF Mono', 'Fira Code', 'Consolas', monospace;
      font-size: 0.9rem;
      padding: 1rem;
      resize: vertical;
      outline: none;
      transition: border-color 0.2s;
    }
    textarea:focus { border-color: #38bdf8; }
    textarea::placeholder { color: #475569; }
    .btn {
      display: inline-block;
      margin-top: 0.75rem;
      padding: 0.6rem 1.5rem;
      background: #2563eb;
      color: #fff;
      border: none;
      border-radius: 6px;
      font-size: 0.9rem;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.2s;
    }
    .btn:hover { background: #1d4ed8; }
    .result-section { margin-top: 2rem; }
    .route-badge {
      display: inline-block;
      padding: 0.35rem 0.85rem;
      border-radius: 20px;
      font-size: 0.8rem;
      font-weight: 600;
      margin-bottom: 1rem;
    }
    .route-mysql { background: #065f46; color: #6ee7b7; }
    .route-snowflake { background: #1e3a5f; color: #7dd3fc; }
    .error {
      background: #450a0a;
      border: 1px solid #7f1d1d;
      color: #fca5a5;
      padding: 0.75rem 1rem;
      border-radius: 8px;
      font-size: 0.85rem;
      margin-bottom: 1rem;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      background: #1e293b;
      border-radius: 8px;
      overflow: hidden;
    }
    th {
      text-align: left;
      padding: 0.65rem 1rem;
      background: #334155;
      color: #94a3b8;
      font-size: 0.75rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    td {
      padding: 0.6rem 1rem;
      border-top: 1px solid #334155;
      font-size: 0.85rem;
      font-family: 'SF Mono', 'Fira Code', monospace;
    }
    tr:hover td { background: #253349; }
    .empty-state {
      text-align: center;
      color: #475569;
      padding: 2rem;
      font-size: 0.9rem;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>SELECT Routing Shim</h1>
    <p class="subtitle">Paste a SELECT query to route between MySQL and Snowflake</p>

    <div class="cutoff-badge">
      Cutoff date: <strong><%= $cutoff %></strong>
      &mdash; queries starting before this go to Snowflake, after to MySQL
    </div>

    <form method="POST" action="/query">
      <textarea name="sql" placeholder="SELECT id, created_at, customer, amount&#10;FROM orders&#10;WHERE created_at BETWEEN '2025-07-01' AND '2026-03-01';"><%= $sql %></textarea>
      <br>
      <button type="submit" class="btn">Run Query</button>
    </form>

    % if ($error) {
      <div class="result-section">
        <div class="error"><%= $error %></div>
      </div>
    % }

    % if ($route) {
      <div class="result-section">
        <span class="route-badge <%= $route =~ /MySQL/ ? 'route-mysql' : 'route-snowflake' %>">
          Routed to: <%= $route %>
        </span>

        % if (@$cols) {
          <table>
            <thead>
              <tr>
                % for my $col (@$cols) {
                  <th><%= $col %></th>
                % }
              </tr>
            </thead>
            <tbody>
              % for my $row (@$rows) {
                <tr>
                  % for my $col (@$cols) {
                    <td><%= $row->{$col} // '' %></td>
                  % }
                </tr>
              % }
            </tbody>
          </table>
        % } else {
          <div class="empty-state">No rows returned</div>
        % }
      </div>
    % }
  </div>
</body>
</html>

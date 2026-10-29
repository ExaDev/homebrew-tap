# The formula of the exadev/homebrew-tap tap (brew install exadev/tap/pg_warren),
# rendered for each release by release/homebrew.py, then again by the
# publish job with only the bottle block `brew bottle --merge --write` added. CONTRIBUTING.md, "Packages".
# Modelled on homebrew-core's pgvector: built for each postgresql@NN it
# depends on, into that formula's extension directories.
class PgWarren < Formula
  desc "Index-free-adjacency traversal and graph compute for PostgreSQL"
  homepage "https://github.com/ExaDev/pg_warren"
  url "https://github.com/ExaDev/pg_warren/releases/download/v0.8.0/pg_warren-0.8.0.tar.gz"
  sha256 "033462805dd33bfcd2d2a94228a146e47b65eddd58a11b95aef360e325a4fef7"
  license "Apache-2.0"

  bottle do
    root_url "https://github.com/ExaDev/pg_warren/releases/download/v0.8.0"
    sha256 cellar: :any, arm64_sequoia: "80c26c02603408b718795240a2db8c9b843a10f0e8a8a4009c6287a92c02f7fc"
  end
  depends_on "postgresql@17" => [:build, :test]
  depends_on "postgresql@18" => [:build, :test]
  depends_on "rust" => :build

  def postgresqls
    deps.map(&:to_formula).sort_by(&:version).select { |f| f.name.start_with?("postgresql@") }
  end

  def install
    system "cargo", "install", "cargo-pgrx", "--version", "0.19.3", "--locked",
           "--root", buildpath/"cargo-pgrx"
    ENV.prepend_path "PATH", buildpath/"cargo-pgrx/bin"
    # The Postgres symbols resolve when the server loads the library.
    ENV.append_to_rustflags "-C link-arg=-Wl,-undefined,dynamic_lookup" if OS.mac?
    ENV["PGRX_HOME"] = buildpath/"pgrx-home"
    postgresqls.each do |postgresql|
      pg_config = postgresql.opt_bin/"pg_config"
      staged = buildpath/"staged-#{postgresql.name}"
      ENV["PGRX_PG_CONFIG_PATH"] = pg_config
      system "cargo", "pgrx", "package", "--manifest-path", "crates/pg_warren/Cargo.toml",
             "--pg-config", pg_config, "--no-default-features", "--features", "pg#{postgresql.version.major}",
             "--out-dir", staged
      pkglibdir = Utils.safe_popen_read(pg_config, "--pkglibdir").chomp
      sharedir = Utils.safe_popen_read(pg_config, "--sharedir").chomp
      (lib/postgresql.name).install Dir["#{staged}#{pkglibdir}/*"]
      (share/postgresql.name/"extension").install Dir["#{staged}#{sharedir}/extension/*"]
    end
  end

  def caveats
    <<~EOS
      pg_warren is built for postgresql@17 and postgresql@18. To use it:
        1. add pg_warren to shared_preload_libraries in postgresql.conf
           (#{var}/postgresql@18/postgresql.conf for postgresql@18):
             shared_preload_libraries = 'pg_warren'
        2. restart PostgreSQL: brew services restart postgresql@18
        3. in each database: CREATE EXTENSION pg_warren;
    EOS
  end

  test do
    ENV["LC_ALL"] = "C"
    postgresqls.each do |postgresql|
      pg_ctl = postgresql.opt_bin/"pg_ctl"
      psql = postgresql.opt_bin/"psql"
      port = free_port
      datadir = testpath/postgresql.name
      system pg_ctl, "initdb", "-D", datadir
      (datadir/"postgresql.conf").write <<~EOS, mode: "a+"
        shared_preload_libraries = 'pg_warren'
        port = #{port}
      EOS
      system pg_ctl, "start", "-D", datadir, "-l", testpath/"log-#{postgresql.name}"
      begin
        system psql, "-p", port.to_s, "-v", "ON_ERROR_STOP=1", "-c", "CREATE EXTENSION pg_warren;",
               "-c", "SELECT warren.version();", "postgres"
      ensure
        system pg_ctl, "stop", "-D", datadir
      end
    end
  end
end

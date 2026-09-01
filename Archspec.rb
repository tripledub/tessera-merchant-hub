# Archspec.rb
source "app/**/*.rb"

architecture :layered, layers: {
  presentation: %w[
    app/controllers/**/*.rb
    app/views/**/*.rb
    app/helpers/**/*.rb
    app/presenters/**/*.rb
    app/channels/**/*.rb
    app/jobs/**/*.rb
  ],
  application: %w[
    app/services/**/*.rb
    app/policies/**/*.rb
    app/mailers/**/*.rb
  ],
  domain: %w[
    app/models/**/*.rb
    app/queries/**/*.rb
  ]
}

# Controller APIs stay in controllers — bare calls to the request context
# from lower layers are reverse dependencies (Rule 2)
application.cannot_call :render, :redirect_to, :params, :session, :cookies, :flash,
                        receiver: :none
domain.cannot_call :render, :redirect_to, :params, :session, :cookies, :flash,
                   receiver: :none

# Domain objects never read execution context — pass explicit parameters
domain.cannot_reference_constants "Current"

# A top-level app/<x>/ folder names a layer or a concept, never a vendor
component(:vendor_folders, in: "app/{sidekiq,temporal,redis,stripe,kafka}/**/*.rb")
  .must_be_empty(because: "vendor code goes one level deeper, e.g. app/services/stripe/")

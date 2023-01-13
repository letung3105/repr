defmodule ReprWeb.Router do
  use ReprWeb, :router

  import ReprWeb.VoterAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ReprWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_voter
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ReprWeb do
    pipe_through :browser

    get "/", PageController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", ReprWeb do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ReprWeb.Telemetry
    end
  end

  # Enables the Swoosh mailbox preview in development.
  #
  # Note that preview only shows emails that were sent by the same
  # node running the Phoenix server.
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ReprWeb do
    pipe_through [:browser, :redirect_if_voter_is_authenticated]

    get "/voters/register", VoterRegistrationController, :new
    post "/voters/register", VoterRegistrationController, :create
    get "/voters/log_in", VoterSessionController, :new
    post "/voters/log_in", VoterSessionController, :create
    get "/voters/reset_password", VoterResetPasswordController, :new
    post "/voters/reset_password", VoterResetPasswordController, :create
    get "/voters/reset_password/:token", VoterResetPasswordController, :edit
    put "/voters/reset_password/:token", VoterResetPasswordController, :update
  end

  scope "/", ReprWeb do
    pipe_through [:browser, :require_authenticated_voter]

    get "/voters/settings", VoterSettingsController, :edit
    put "/voters/settings", VoterSettingsController, :update
    get "/voters/settings/confirm_email/:token", VoterSettingsController, :confirm_email
  end

  scope "/", ReprWeb do
    pipe_through [:browser]

    delete "/voters/log_out", VoterSessionController, :delete
    get "/voters/confirm", VoterConfirmationController, :new
    post "/voters/confirm", VoterConfirmationController, :create
    get "/voters/confirm/:token", VoterConfirmationController, :edit
    post "/voters/confirm/:token", VoterConfirmationController, :update
  end
end

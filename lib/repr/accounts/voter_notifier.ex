defmodule Repr.Accounts.VoterNotifier do
  import Swoosh.Email

  alias Repr.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Repr", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(voter, url) do
    deliver(voter.email, "Confirmation instructions", """

    ==============================

    Hi #{voter.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset a voter password.
  """
  def deliver_reset_password_instructions(voter, url) do
    deliver(voter.email, "Reset password instructions", """

    ==============================

    Hi #{voter.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to update a voter email.
  """
  def deliver_update_email_instructions(voter, url) do
    deliver(voter.email, "Update email instructions", """

    ==============================

    Hi #{voter.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end
end

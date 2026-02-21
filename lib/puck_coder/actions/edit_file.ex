defmodule PuckCoder.Actions.EditFile do
  @moduledoc """
  Action struct for editing a file.
  """
  defstruct action: "edit_file", path: nil, old_string: nil, new_string: nil, description: nil
end

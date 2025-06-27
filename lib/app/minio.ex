defmodule App.Minio do
  @bucket "chat-images"

  def upload_file(path, filename) do
    {:ok, file_binary} = File.read(path)
    ExAws.S3.put_object(@bucket, filename, file_binary, acl: :public_read)
    |> ExAws.request()
    |> case do
      {:ok, _} ->
        {:ok, public_url(filename)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def public_url(filename) do
    "http://localhost:9000/#{@bucket}/#{filename}"
  end
end

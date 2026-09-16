require "fileutils"

Jekyll::Hooks.register :site, :post_write do |site|
  source_root = File.join(site.source, "ai")
  next unless Dir.exist?(source_root)

  Dir[File.join(source_root, "**", "*.md")].each do |source_path|
    relative_path = source_path.delete_prefix("#{source_root}/")
    destination_path = File.join(site.dest, "ai", relative_path)
    FileUtils.mkdir_p(File.dirname(destination_path))
    FileUtils.cp(source_path, destination_path)
  end
end

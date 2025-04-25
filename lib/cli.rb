require_relative 'painting_extractor'

module CLI
  def self.run(args)
    if args.empty? || args.include?('-h') || args.include?('--help')
      show_help
      return
    end

    html_file = args.first
    output_file = args[1] || 'output.json'

    unless File.exist?(html_file)
      puts "Error: HTML file '#{html_file}' not found."
      return
    end

    puts "Processing '#{html_file}'..."
    extractor = PaintingExtractor.new(html_file, output_file)

    begin
      extractor.extract_and_save
      puts "Successfully extracted paintings to '#{output_file}'."
    rescue StandardError => e
      puts "Error: #{e.message}"
      puts e.backtrace.join("\n") if args.include?('--debug')
    end
  end

  def self.show_help
    puts <<~HELP
      Van Gogh Paintings Extractor

      Usage:
        ruby extract.rb <html_file> [output_file] [options]

      Arguments:
        html_file    Path to the HTML file containing Van Gogh paintings information
        output_file  Path to save the extracted JSON data (default: output.json)

      Options:
        -h, --help   Show this help message
        --debug      Show detailed error messages if an error occurs
    HELP
  end
end

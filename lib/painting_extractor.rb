require 'nokogiri'
require 'json'
require 'base64'
require 'uri'
require 'open-uri'
require 'cgi'
require 'selenium-webdriver' # Required for handling JavaScript-rendered content

class PaintingExtractor
  attr_reader :html_file, :output_file

  # HTML element selectors for finding painting data in the Google search results
  SELECTOR_MAP = {
    # Main carousel-related selectors
    carousel_container: 'Cz5hV',  # The outer container for the painting carousel
    artwork_item: 'iELo6',        # Individual artwork containers in the carousel
    artwork_image: 'taFZJe',      # The image element within each artwork
    artwork_details: 'KHK6lb',    # Container holding painting details (name, year)
    artwork_title: 'pgNMRc',      # Element containing the painting's title
    artwork_year: 'cxzHyb',       # Element containing the painting's year
  }

  def initialize(html_file, output_file = nil)
    @html_file = html_file
    @output_file = output_file || 'output.json'
  end

  def extract
    # First, check if the HTML file exists
    # This will raise ENOENT if the file doesn't exist
    File.stat(@html_file) unless File.exist?(@html_file)

    # Configure Chrome WebDriver options for headless operation
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless=new') # Use new headless mode for Chrome
    options.add_argument('--disable-gpu') # Disable GPU acceleration (recommended for headless)
    options.add_argument('--allow-file-access-from-files') # Allow access to local files
    options.add_argument('--allow-file-access') # Additional file access permission
    options.add_argument('--no-sandbox') # Bypass OS security model
    options.add_argument('--disable-dev-shm-usage') # Overcome limited /dev/shm in some environments

    # Initialize the Chrome driver with specified options
    driver = Selenium::WebDriver.for :chrome, options: options

    # Convert relative path to absolute path and navigate to the HTML file
    file_path = File.expand_path(@html_file)
    driver.navigate.to "file://#{file_path}"

    # Wait for JavaScript to execute and images to load
    # This ensures dynamic content is properly rendered
    sleep(2)

    # Parse the rendered HTML with Nokogiri
    doc = Nokogiri::HTML(driver.page_source)

    # Extract and return paintings data from the parsed HTML
    result = extract_paintings_from_carousel(doc)

    # Clean up WebDriver resources
    driver.quit

    result
  end

  def extract_and_save
    result = extract

    # Wrap the result in a hash with 'artworks' key
    data_to_save = { 'artworks' => result }

    save_to_json(data_to_save)

    # Return true if successful
    true
  end

  private

  def extract_paintings_from_carousel(doc)
    paintings = []

    # First strategy: Try to extract from main carousel
    carousel = doc.css(".#{SELECTOR_MAP[:carousel_container]}")
    unless carousel.empty?
      artwork_items = carousel.css(".#{SELECTOR_MAP[:artwork_item]}")
      artwork_items.each do |item|
        # Get the first image element - we'll handle placeholder detection later
        # This is more reliable as some images might be lazy-loaded with data-src
        img = item.css(".#{SELECTOR_MAP[:artwork_image]}").first

        # Extract details
        details = item.css(".#{SELECTOR_MAP[:artwork_details]}")

        title = details.css(".#{SELECTOR_MAP[:artwork_title]}").text.strip
        year_text = details.css(".#{SELECTOR_MAP[:artwork_year]}").text.strip

        # Use the full year text rather than trying to parse it
        # This preserves information like "circa 1889" or date ranges
        year = year_text

        # Get image source URL
        image_url = img ? img['src'] : nil
        # Create painting entry with the proper format
        painting = {
          'name' => title
        }
        # Store the year text as extensions
        painting['extensions'] = year

        # Extract the actual link from the anchor tag if available,
        # fallback to a Google search link if not found
        link_tag = item.at('a')
        link = link_tag ? link_tag['href'] : nil
        final_link = link ? absolute_google_link(link) : "https://www.google.com/search?q=#{CGI.escape(title)}"

        painting['link'] = final_link

        # Handle lazy-loaded images by checking for data-src attribute
        # when the src attribute contains a placeholder image
        painting['image'] = placeholder_image?(image_url) ? img['data-src'] : image_url

        paintings << painting
      end
    end
    # Ensure unique paintings by name
    paintings.uniq! { |p| p['name'] }

    # Ensure the result matches the expected format
    format_paintings_for_output(paintings)
  end

  def format_paintings_for_output(paintings)
    # Format each painting to match the expected output structure
    paintings.map do |painting|
      # Start with the name property
      result = { 'name' => painting['name'] }

      # Insert extensions immediately after name to maintain the expected order in the JSON
      # Ensure extensions is an array as required by the expected format
      result['extensions'] = [painting['extensions']] if painting['extensions'] && !painting['extensions'].empty?

      # Then add the other keys in the expected order
      result['link'] = painting['link']
      result['image'] = painting['image']

      result
    end
  end

  def save_to_json(data)
    json_content = JSON.pretty_generate(data)
    # Ensure the file ends with a newline
    json_content += "\n" unless json_content.end_with?("\n")
    File.write(@output_file, json_content)
  end

  # Helper method to identify placeholder images
  # Often, image carousels use placeholder images before loading the real content
  def placeholder_image?(src)
    return true if src.nil? || src.empty?

    # Common placeholder gif base64 string patterns
    src.include?('R0lGODlhAQABAIAAAP') || src.include?('data:image/gif;base64')
  end

  # Helper method to convert relative Google links to absolute URLs
  # Ensures all links are properly formatted with the Google domain
  def absolute_google_link(href)
    return nil unless href

    href.start_with?('http') ? href : "https://www.google.com#{href}"
  end
end

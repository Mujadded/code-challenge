require 'spec_helper'
require_relative '../lib/painting_extractor'

RSpec.describe PaintingExtractor do
  let(:sample_html_file) { 'fixtures/sample.html' }
  let(:output_file) { 'tmp/test_output.json' }
  let(:extractor) { PaintingExtractor.new(sample_html_file, output_file) }

  before do
    # Create tmp directory if it doesn't exist
    Dir.mkdir('tmp') unless Dir.exist?('tmp')

    # Mock Selenium setup to avoid actual browser instantiation in tests
    allow_any_instance_of(Selenium::WebDriver::Chrome::Driver).to receive(:navigate).and_return(double(to: nil))
    allow_any_instance_of(Selenium::WebDriver::Chrome::Driver).to receive(:page_source).and_return(File.read(sample_html_file))
    allow_any_instance_of(Selenium::WebDriver::Chrome::Driver).to receive(:quit).and_return(nil)
  end

  after do
    # Clean up test output file
    File.delete(output_file) if File.exist?(output_file)
  end

  describe '#initialize' do
    it 'sets html_file and output_file' do
      expect(extractor.html_file).to eq(sample_html_file)
      expect(extractor.output_file).to eq(output_file)
    end

    it 'uses default output file when not specified' do
      default_extractor = PaintingExtractor.new(sample_html_file)
      expect(default_extractor.output_file).to eq('output.json')
    end
  end

  describe '#extract' do
    it 'returns an array of paintings' do
      paintings = extractor.extract
      expect(paintings).to be_an(Array)
    end

    it 'extracts painting data correctly' do
      paintings = extractor.extract

      expect(paintings.length).to eq(4)

      # Check first painting (The Starry Night)
      expect(paintings[0]['name']).to eq('The Starry Night')
      expect(paintings[0]['extensions']).to eq(['1889'])
      expect(paintings[0]['link']).to eq('https://www.google.com/search?q=the+starry+night+van+gogh')
      # The image might be the data-src attribute
      expect(paintings[0]['image']).to eq('https://example.com/starry-night.jpg')

      # Check second painting (Sunflowers)
      expect(paintings[1]['name']).to eq('Sunflowers')
      expect(paintings[1]['extensions']).to eq(['1888'])
      expect(paintings[1]['link']).to eq('https://example.com/sunflowers')
      expect(paintings[1]['image']).to eq('https://example.com/sunflowers.jpg')

      # Check third painting (Self-Portrait)
      expect(paintings[2]['name']).to eq('Self-Portrait')
      expect(paintings[2]['extensions']).to eq(['1889'])
      expect(paintings[2]['link']).to eq('https://www.google.com/search?q=self+portrait+van+gogh')
      expect(paintings[2]['image']).to eq('https://example.com/self-portrait.jpg')

      # Check fourth painting (The Potato Eaters)
      expect(paintings[3]['name']).to eq('The Potato Eaters')
      expect(paintings[3]['extensions']).to eq(['1885'])
      # No link provided in HTML, so it should use a search link based on the title
      expect(paintings[3]['link']).to eq('https://www.google.com/search?q=The+Potato+Eaters')
      expect(paintings[3]['image']).to eq('https://example.com/potato-eaters.jpg')
    end

    it 'handles placeholder images correctly' do
      # Create a simplified test case focused on the placeholder detection logic
      simple_doc = Nokogiri::HTML(<<-HTML
        <div class="Cz5hV">
          <div class="iELo6">
            <img class="taFZJe src="data:image/gif;base64,R0lGODlhAQABAIAAAP///////yH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==" data-src="real-image.jpg">
            <div class="KHK6lb">
              <div class="pgNMRc">Test Painting</div>
              <div class="cxzHyb">1889</div>
            </div>
          </div>
        </div>
      HTML
      )

      # Use the extractor directly with our test document
      allow_any_instance_of(PaintingExtractor).to receive(:extract_paintings_from_carousel).and_call_original
      allow(extractor).to receive(:extract).and_return(extractor.send(:extract_paintings_from_carousel, simple_doc))

      # Now test the output
      paintings = extractor.extract
      expect(paintings.length).to eq(1)
      expect(paintings[0]['name']).to eq('Test Painting')
      expect(paintings[0]['image']).to eq('real-image.jpg')
    end

    it 'formats links correctly' do
      paintings = extractor.extract
      # Relative links should be converted to absolute Google URLs
      expect(paintings[0]['link']).to eq('https://www.google.com/search?q=the+starry+night+van+gogh')
      # Absolute links should remain unchanged
      expect(paintings[1]['link']).to eq('https://example.com/sunflowers')
      # Missing links should generate a search link based on the title
      # Note: CGI.escape uses + for spaces, not %20
      expect(paintings[3]['link']).to eq('https://www.google.com/search?q=The+Potato+Eaters')
    end

    context 'when HTML file does not exist' do
      let(:nonexistent_file) { 'nonexistent.html' }
      let(:invalid_extractor) { PaintingExtractor.new(nonexistent_file) }

      it 'raises an error' do
        expect { invalid_extractor.extract }.to raise_error(Errno::ENOENT)
      end
    end
  end

  describe '#extract_and_save' do
    it 'creates an output file' do
      extractor.extract_and_save
      expect(File.exist?(output_file)).to be true
    end

    it 'saves valid JSON' do
      extractor.extract_and_save
      json_content = File.read(output_file)
      expect { JSON.parse(json_content) }.not_to raise_error
    end

    it 'wraps paintings in an artworks key' do
      extractor.extract_and_save
      json_content = File.read(output_file)
      data = JSON.parse(json_content)

      expect(data).to have_key('artworks')
      expect(data['artworks']).to be_an(Array)
      expect(data['artworks'].length).to eq(4)
    end
  end

  describe 'private methods' do
    describe '#placeholder_image?' do
      it 'identifies base64 placeholders correctly' do
        placeholder = 'data:image/gif;base64,R0lGODlhAQABAIAAAP'
        expect(extractor.send(:placeholder_image?, placeholder)).to be true
      end

      it 'identifies empty src as placeholder' do
        empty_src = ''
        expect(extractor.send(:placeholder_image?, empty_src)).to be true
      end

      it 'returns false for regular image urls' do
        real_image = 'https://example.com/image.jpg'
        expect(extractor.send(:placeholder_image?, real_image)).to be false
      end
    end

    describe '#absolute_google_link' do
      it 'converts relative links to absolute Google URLs' do
        relative = '/search?q=test'
        expect(extractor.send(:absolute_google_link, relative)).to eq('https://www.google.com/search?q=test')
      end

      it 'preserves absolute URLs' do
        absolute = 'https://example.com/test'
        expect(extractor.send(:absolute_google_link, absolute)).to eq('https://example.com/test')
      end

      it 'handles nil values' do
        expect(extractor.send(:absolute_google_link, nil)).to be_nil
      end
    end
  end
end

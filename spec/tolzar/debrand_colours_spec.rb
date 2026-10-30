require 'rails_helper'

# Debrand (#9): records created without a colour (API, imports) get Tolzar's colour, not upstream's #1f93ff.
RSpec.describe 'Tolzar default colours' do
  it 'defaults a new website widget and a new label to #3E63DD' do
    expect(Channel::WebWidget.new.widget_color).to eq('#3E63DD')
    expect(Label.new.color).to eq('#3E63DD')
  end

  it 'keeps a colour that was chosen' do
    expect(Channel::WebWidget.new(widget_color: '#112233').widget_color).to eq('#112233')
    expect(Label.new(color: '#445566').color).to eq('#445566')
  end
end

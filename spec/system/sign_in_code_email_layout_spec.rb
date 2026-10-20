# frozen_string_literal: true

require "rails_helper"

# MH-414: on a narrow phone the six digits of the sign-in code wrapped onto two
# lines. This renders the delivered email in a real browser at phone widths, with
# the text scaled up the way a mail app's larger text setting does it (font sizes
# and letter spacing grow, widths and padding do not) and allowing a long word to
# break wherever it overflows, which Gmail's message view does (`word-wrap:
# break-word`), and checks the code stays on one line.
RSpec.describe "Sign-in code email layout", type: :system do
  let(:record) { create(:applicant_sign_in_code, email: "invitee@example.com", code: "644871") }
  let(:encrypted) do
    ShortLivedSecret.encrypt("644871", purpose: ApplicantSignInCode::MAIL_PURPOSE, expires_in: ApplicantSignInCode::MAIL_TOKEN_LIFETIME)
  end
  let(:preview_path) { Rails.root.join("tmp/sign_in_code_email_preview.html") }

  before do
    ApplicantSignInCodeMailer.code(record, encrypted).deliver_now
    File.write(preview_path, ActionMailer::Base.deliveries.last.html_part.body.decoded)
  end

  after { FileUtils.rm_f(preview_path) }

  def simulate_mail_app(factor)
    page.execute_script(<<~JS)
      document.body.style.overflowWrap = "anywhere"
      const elements = Array.from(document.querySelectorAll("body, body *"))
      const sizes = elements.map((el) => {
        const style = getComputedStyle(el)
        return [parseFloat(style.fontSize), parseFloat(style.letterSpacing) || 0, parseFloat(style.lineHeight)]
      })
      elements.forEach((el, i) => {
        el.style.fontSize = `${sizes[i][0] * #{factor}}px`
        el.style.letterSpacing = `${sizes[i][1] * #{factor}}px`
        if (!Number.isNaN(sizes[i][2])) el.style.lineHeight = `${sizes[i][2] * #{factor}}px`
      })
    JS
  end

  def code_line_count
    page.evaluate_script(<<~JS)
      (() => {
        const range = document.createRange()
        range.selectNodeContents(document.querySelector(".email-code"))
        return new Set(Array.from(range.getClientRects()).map((rect) => Math.round(rect.top))).size
      })()
    JS
  end

  def code_overflows_its_box?
    page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector(".email-code")
        return box.scrollWidth > box.clientWidth + 1
      })()
    JS
  end

  [ [ 320, 1.0 ], [ 320, 1.6 ], [ 320, 2.0 ], [ 360, 1.6 ], [ 360, 2.0 ], [ 390, 2.0 ], [ 480, 1.0 ] ].each do |width, scale|
    it "keeps the six digits on one line, inside their box, at #{width}px with text scaled #{scale}x" do
      page.driver.resize(width, 900)
      visit "file://#{preview_path}"
      simulate_mail_app(scale)

      expect(page).to have_css(".email-code", text: "644871")
      expect(code_line_count).to eq(1)
      expect(code_overflows_its_box?).to be(false)
    end
  end

  it "stays large enough to read and copy" do
    visit "file://#{preview_path}"

    size = page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('.email-code')).fontSize)")
    expect(size).to be >= 24
  end
end

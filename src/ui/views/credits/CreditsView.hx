package ui.views.credits;

import h2d.Object;
import h2d.Text;
import h2d.Bitmap;
import h2d.Interactive;
import ui.FontManager;
import ui.UIIcons;
import ui.components.UITheme;
import Version;

/**
 * Game development credits, authorship attribution, and technology disclosure view.
 */
class CreditsView extends Object {
    /** Title banner display. */
    public var titleText:Text;

    /** Lead architect section labels. */
    public var leadTitleText:Text;
    public var leadNameText:Text;
    public var devBadge:Bitmap;

    /** Publishing section labels. */
    public var pubTitleText:Text;
    public var pubNameText:Text;

    /** AI collaboration section labels. */
    public var aiTitleText:Text;
    public var aiNameText:Text;

    /** Framework and font technical disclosures. */
    public var techDetailsText:Text;

    /** Build version badge display. */
    public var versionText:Text;

    /** Return back navigation button. */
    public var backBtnText:Text;
    public var backInteractive:Interactive;

    /** Color branding for lead developer. */
    public static inline var COLOR_LEAD_DEV:Int = UITheme.COLOR_ACCENT_CYAN;

    /** Color branding for in-house studio publisher. */
    public static inline var COLOR_PUBLISHER:Int = 0xE5C07B;

    /** Color branding for AI engineering collaboration. */
    public static inline var COLOR_AI_COLLAB:Int = 0x98C379;

    /** Max text wrap boundary width for legal disclosure paragraph in pixels. */
    public static inline var MAX_TECH_DETAILS_WIDTH:Float = 820.0;

    /** Callback invoked upon requesting return to main menu. */
    public var onBack:Void->Void;

    /**
     * Instantiates the credits screen view.
     *
     * @param parent Optional parent 2D scene object.
     */
    public function new(?parent:Object) {
        super(parent);

        titleText = new Text(FontManager.heroFont, this);
        titleText.text = "M.O.B. // MOTORS ON BOOST";
        titleText.textColor = UITheme.COLOR_ACCENT_ORANGE;

        leadTitleText = new Text(FontManager.regularFont, this);
        leadTitleText.text = "LEAD ARCHITECT & TECHNICAL DESIGNER";
        leadTitleText.textColor = UITheme.COLOR_TEXT_MUTED;

        leadNameText = new Text(FontManager.titleFont, this);
        leadNameText.text = "Gerard \"Jamie\" (Jagofr) Francis";
        leadNameText.textColor = COLOR_LEAD_DEV;

        devBadge = new Bitmap(UIIcons.get(UIIcons.IconType.Credits, UITheme.ICON_SIZE_CREDITS, COLOR_LEAD_DEV), this);

        pubTitleText = new Text(FontManager.regularFont, this);
        pubTitleText.text = "PUBLISHED & DEVELOPED IN-HOUSE BY";
        pubTitleText.textColor = UITheme.COLOR_TEXT_MUTED;

        pubNameText = new Text(FontManager.titleFont, this);
        pubNameText.text = "RvL // ROGUE";
        pubNameText.textColor = COLOR_PUBLISHER;

        aiTitleText = new Text(FontManager.regularFont, this);
        aiTitleText.text = "AI ENGINEERING COLLABORATION";
        aiTitleText.textColor = UITheme.COLOR_TEXT_MUTED;

        aiNameText = new Text(FontManager.regularFont, this);
        aiNameText.text = "Google Gemini 3.8 Flash";
        aiNameText.textColor = COLOR_AI_COLLAB;

        techDetailsText = new Text(FontManager.regularFont, this);
        techDetailsText.textAlign = Center;
        techDetailsText.maxWidth = MAX_TECH_DETAILS_WIDTH;
        techDetailsText.textColor = 0xA0B2C6;
        techDetailsText.text = 
            "Built with Haxe, Heaps.io (Hardware-Accelerated WebGL) & Modern Shaders\n" +
            "Typography: Stack Sans Headline & Material Symbols Sharp\n" +
            "Homage & Inspiration: Need for Speed: Most Wanted (2005) & Burnout Revenge (2005)\n\n" +
            "Thank you for playing!";

        versionText = new Text(FontManager.regularFont, this);
        versionText.text = Version.DISPLAY;
        versionText.textColor = COLOR_PUBLISHER;
        versionText.textAlign = Center;

        backBtnText = new Text(FontManager.titleFont, this);
        backBtnText.text = "> BACK TO MAIN MENU <";
        backBtnText.textColor = UITheme.COLOR_ACCENT_CYAN;

        backInteractive = new Interactive(420, 46, this);
        backInteractive.onClick = function(_) {
            if (visible && onBack != null) onBack();
        };
    }

    /**
     * Activates the credits screen view.
     */
    public function activate() {
        visible = true;
    }

    /**
     * Positions credits text elements and developer emblem relative to screen bounds.
     *
     * @param sw Screen width in pixels.
     * @param sh Screen height in pixels.
     */
    public function layout(sw:Float, sh:Float) {
        if (titleText != null) {
            titleText.x = (sw - titleText.textWidth) * 0.5;
            titleText.y = sh * 0.15;
        }
        if (leadTitleText != null) {
            leadTitleText.x = (sw - leadTitleText.textWidth) * 0.5;
            leadTitleText.y = sh * 0.23;
        }
        if (leadNameText != null && devBadge != null) {
            var comboWidth = leadNameText.textWidth + 38;
            var startX = (sw - comboWidth) * 0.5;

            devBadge.x = startX;
            devBadge.y = sh * 0.27 + 2;

            leadNameText.x = startX + 38;
            leadNameText.y = sh * 0.27;
        }
        if (pubTitleText != null) {
            pubTitleText.x = (sw - pubTitleText.textWidth) * 0.5;
            pubTitleText.y = sh * 0.36;
        }
        if (pubNameText != null) {
            pubNameText.x = (sw - pubNameText.textWidth) * 0.5;
            pubNameText.y = sh * 0.40;
        }
        if (aiTitleText != null) {
            aiTitleText.x = (sw - aiTitleText.textWidth) * 0.5;
            aiTitleText.y = sh * 0.48;
        }
        if (aiNameText != null) {
            aiNameText.x = (sw - aiNameText.textWidth) * 0.5;
            aiNameText.y = sh * 0.52;
        }
        if (techDetailsText != null) {
            techDetailsText.x = (sw - techDetailsText.textWidth) * 0.5;
            techDetailsText.y = sh * 0.58;
        }
        if (versionText != null) {
            versionText.x = (sw - versionText.textWidth) * 0.5;
            versionText.y = sh * 0.70;
        }
        if (backBtnText != null) {
            backBtnText.x = (sw - backBtnText.textWidth) * 0.5;
            backBtnText.y = sh * 0.77;
            backInteractive.x = backBtnText.x - 20;
            backInteractive.y = backBtnText.y - 4;
            backInteractive.width = backBtnText.textWidth + 40;
            backInteractive.height = 46;
        }
    }
}

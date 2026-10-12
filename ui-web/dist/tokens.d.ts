/**
 * Design tokens for the Skip a Brainrot HUD — a direct port of
 * `ReplicatedStorage/Modules/UIKit/Tokens.lua`. Names and values match the Luau
 * source one-for-one so a change on either side is a visible diff on the other.
 *
 * Current style: the 2026-08-04 "Roblox Simulator UI Style Guide" pass —
 * Pet-Simulator-inspired. Light gray window, ONE red header, dark gray slots,
 * 4px near-black outer stroke with a 2px white inner keyline.
 *
 * Design canvas: 1350 x 775. Every number below is offset px at that size.
 */
/** Vertical gradient stops, top -> bottom. Roblox `UIGradient` at Rotation 90. */
export type GradientStops = readonly string[];
export declare const canvas: {
    readonly width: 1350;
    readonly height: 775;
};
export declare const color: {
    readonly outline: "#202020";
    readonly innerKeyline: "#FFFFFF";
    readonly panelTop: "#D6D6D6";
    readonly panelBottom: "#A9A9A9";
    readonly subPanelTop: "#C4C4C4";
    readonly subPanelBottom: "#9C9C9C";
    readonly rowTop: "#4A4A4A";
    readonly rowBottom: "#363636";
    readonly tabTop: "#BEBEBE";
    readonly tabBottom: "#9C9C9C";
    readonly trackTop: "#2E2E2E";
    readonly trackBottom: "#3A3A3A";
    readonly slotTop: "#4A4A4A";
    readonly slotBottom: "#363636";
    readonly headerTop: "#F96B57";
    readonly headerBottom: "#C84535";
    readonly white: "#FFFFFF";
    readonly textMuted: "#D8D8D8";
    readonly textAccent: "#FFD84D";
    readonly textOnLight: "#2A2A2A";
    readonly textOnWindow: "#2A2A2A";
    readonly textOnGoldCard: "#3A2A05";
    readonly textOnGoldChrome: "#5A4A12";
    readonly textDisabled: "#B8C4A4";
    readonly textClaimed: "#9FAE8B";
    readonly claimRing: "#7CE04A";
    readonly activeRing: "#FFD84D";
    /** Nav-rail active radial glow. Distinct from `activeRing`, which panels' tabs use. */
    readonly activeGlow: "#FFE87A";
    readonly scrollThumb: "#9FAE8B";
    readonly rarityCommon: "#C9CCC2";
    readonly rarityRare: "#3FA9F5";
    readonly rarityEpic: "#A855F7";
    readonly rarityLegend: "#FFB200";
};
/** Modal scrim. Roblox sets BackgroundTransparency 0.50, i.e. 50% opaque. */
export declare const scrim: {
    readonly color: "#0A0E06";
    readonly alpha: 0.5;
};
export declare const gradient: {
    readonly gold: readonly ["#FFE87A", "#FFC531", "#E08A0C"];
    readonly goldSmall: readonly ["#FFE066", "#FFC531", "#E8930F"];
    readonly green: readonly ["#83E34A", "#4FB42E"];
    readonly purple: readonly ["#DE93FF", "#B04CEC", "#7C1CC0"];
    readonly red: readonly ["#FF6B6B", "#D83E3E"];
    readonly blue: readonly ["#56B7FF", "#2E81D8"];
    readonly gem: readonly ["#D98BFF", "#A93FE6", "#7A1CB8"];
    readonly panel: readonly ["#D6D6D6", "#A9A9A9"];
    readonly subPanel: readonly ["#C4C4C4", "#9C9C9C"];
    readonly row: readonly ["#4A4A4A", "#363636"];
    readonly tab: readonly ["#BEBEBE", "#9C9C9C"];
    readonly track: readonly ["#2E2E2E", "#3A3A3A"];
    readonly slot: readonly ["#4A4A4A", "#363636"];
    readonly header: readonly ["#F96B57", "#C84535"];
    readonly window: readonly ["#D6D6D6", "#A9A9A9"];
    readonly freeCard: readonly ["#F7F7F1", "#DEDED4", "#B2B4A8"];
    /** Legacy alias — the pre-2026-08-04 cream body, now pointing at the window gray. */
    readonly cream: readonly ["#D6D6D6", "#A9A9A9"];
    readonly passCard: readonly ["#FFE066", "#F7B62C", "#D8860E"];
    readonly lockBadge: readonly ["#F2F2EC", "#C2C4B8"];
    readonly knob: readonly ["#FFF0A8", "#FFC531"];
    readonly disabled: readonly ["#6A7757", "#454F33"];
    readonly ownedCta: readonly ["#8FA378", "#54643C"];
    readonly freeLabel: readonly ["#7A8A66", "#55643F"];
    readonly passLabel: readonly ["#FFD84D", "#E0912A"];
};
export type GradientName = keyof typeof gradient;
/** Outer stroke widths. Guide: "outer stroke 4px dark gray, inner stroke 1-2px white". */
export declare const stroke: {
    readonly panel: 4;
    readonly control: 3;
    readonly chip: 3;
    readonly hairline: 2;
    readonly inner: 2;
};
/** Guide: "Panels 8px, Buttons 10-14px, Slots 8px". */
export declare const radius: {
    readonly panel: 8;
    readonly control: 12;
    readonly inner: 10;
    readonly small: 10;
    readonly chip: 10;
    readonly slot: 8;
    readonly art: 8;
    readonly pill: 999;
};
/** Hard offset shadow distance = stroke + 1. */
export declare const shadowOffset: {
    readonly panel: 6;
    readonly control: 5;
    readonly chip: 4;
};
/**
 * Top white gloss strip and bottom dark shade.
 * `alpha`/`alphaLight` are opacities; `shadeAlpha` is Roblox BackgroundTransparency,
 * so the shade renders at `1 - shadeAlpha` opacity.
 */
export declare const gloss: {
    readonly height: 5;
    readonly alpha: 0.45;
    readonly alphaLight: 0.3;
    readonly shadeHeight: 6;
    readonly shadeAlpha: 0.82;
};
export declare const pad: {
    readonly panel: 16;
    readonly panelWide: 18;
    readonly gap: 12;
    readonly gapTight: 8;
    readonly gridGap: 11;
    readonly rowGap: 10;
};
export declare const size: {
    readonly headerHeight: 92;
    readonly headerIcon: 64;
    readonly closeButton: {
        readonly width: 74;
        readonly height: 66;
    };
    /** v2 rail: a bare floating icon in a 106px column, no button plate. */
    readonly railItem: 106;
    readonly railIcon: 66;
    readonly railGap: 6;
    readonly railInset: 10;
    readonly railGlow: 88;
    readonly railSide: "left";
    readonly currencyPill: 54;
    readonly rewardCard: {
        readonly width: 178;
        readonly height: 186;
    };
    readonly tierBadge: 58;
    readonly lockBadge: 46;
    readonly claimPill: 38;
    readonly bagSlot: 118;
    readonly dayCard: 196;
    readonly questRow: 88;
    readonly panelWidth: {
        readonly pass: 960;
        readonly backpack: 960;
        readonly settings: 700;
        readonly daily: 800;
        readonly index: 940;
        readonly goals: 860;
        readonly eggs: 940;
    };
    /** Reserves the nav rail column. */
    readonly panelRightGutter: 132;
};
/**
 * Type ramp as `[size, textStrokeThickness]`, matching `T.text` in the Luau source.
 * Guide: "Titles 28-34, Buttons 18-24, Labels 14-18".
 */
export declare const text: {
    readonly panelTitle: readonly [32, 3];
    readonly buttonL: readonly [24, 2.5];
    readonly buttonM: readonly [20, 2];
    readonly value: readonly [22, 2];
    readonly cardLabel: readonly [17, 2];
    readonly chip: readonly [14, 1.5];
    readonly railLabel: readonly [20, 4];
    /** Body copy — no stroke. */
    readonly meta: readonly [14, 0];
};
export type TextStyle = keyof typeof text;
/**
 * Display face is Fredoka One, body is Nunito — the families the design handoff
 * kit uses. In Roblox both fall back to GothamBold, which is what the engine has.
 */
export declare const font: {
    readonly display: "'Fredoka One', system-ui, sans-serif";
    readonly ui: "'Nunito', system-ui, sans-serif";
};
/** Durations in ms; Roblox `TweenInfo` seconds x1000. */
export declare const tween: {
    readonly hover: 120;
    readonly press: 80;
    readonly panelOpen: 180;
    readonly panelClose: 120;
    readonly scrim: 150;
    readonly pop: 220;
    readonly fly: 380;
    readonly bar: 400;
    readonly pulsePeriod: 1600;
    readonly bobPeriod: 1400;
    readonly claimStagger: 60;
};
export declare const zIndex: {
    readonly world: 0;
    readonly currency: 20;
    readonly panel: 25;
    readonly rail: 30;
    readonly kit: 50;
    readonly toast: 80;
};
/** CSS `linear-gradient` for a named token gradient, top -> bottom. */
export declare function gradientCss(name: GradientName): string;

import * as React from 'react';

/**
 * Icon — from @skip-a-brainrot/ui@1.0.0.
 */
export interface IconProps {
  /** Which icon to render. */
  name: "bag" | "coin" | "daily" | "eggs" | "gem" | "goals" | "index" | "pass" | "plot" | "settings" | "shops" | "skip";
  /** Width and height in px. Defaults to filling its container. */
  size?: number;
  className?: string;
  id?: string;
  style?: CSSProperties;
  children?: React.ReactNode;
  /** Allows getting a ref to the component instance. Once the component unmounts, React will set `ref.current` to `null` (or  */
  ref?: string | ((instance: SVGSVGElement) => void | DO_NOT_USE_OR_YOU_WILL_BE_FIRED_CALLBACK_REF_RETURN_VALUES[keyof DO_NOT_USE_OR_YOU_WILL_BE_FIRED_CALLBACK_REF_RETURN_VALUES]) | RefObject<SVGSVGElement>;
}

export declare const Icon: React.ComponentType<IconProps>;

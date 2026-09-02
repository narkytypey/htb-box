import * as React from 'react';

export interface PortalNavItem {
  /** Uppercase link text. */
  label: string;
  /** Destination; omit for the section the user is already in. */
  href?: string;
  /** Paints the item `--orange` to mark the active section. */
  current?: boolean;
}

export interface PortalNavProps {
  /** Sections in bar order. Exactly one should carry `current`. */
  items: PortalNavItem[];
}

/**
 * The uppercase section links that sit at the right of the `PortalBar`.
 *
 * Items are grey (`#aaa`) at rest, white on hover, and `--orange` when
 * `current` - the only colour cue for where you are in the portal.
 */
export function PortalNav({ items }: PortalNavProps) {
  return (
    <nav className="portal-nav">
      {items.map((item, i) =>
        item.href ? (
          <a key={i} href={item.href} className={item.current ? 'current' : undefined}>
            {item.label}
          </a>
        ) : (
          <span key={i} className={item.current ? 'current' : undefined}>
            {item.label}
          </span>
        )
      )}
    </nav>
  );
}

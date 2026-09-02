import * as React from 'react';
import { BrandLockup } from '@donerup/ui';

export const InPortalBar = () => (
  <div style={{ background: 'var(--black)', padding: '16px 28px' }}>
    <BrandLockup onDark />
  </div>
);

export const InLoginHero = () => (
  <div style={{ background: 'var(--black)', padding: '40px 32px' }}>
    <BrandLockup onDark />
  </div>
);

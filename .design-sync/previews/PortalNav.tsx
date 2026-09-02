import * as React from 'react';
import { PortalNav } from '@donerup/ui';

export const DashboardSections = () => (
  <div style={{ background: 'var(--black)', padding: '18px 22px' }}>
    <PortalNav
      items={[
        { label: 'Store Ops' },
        { label: 'Reports', href: '/admin/report-template' },
        { label: 'Branding', href: '/admin/branding' },
        { label: 'Directory', current: true },
      ]}
    />
  </div>
);

export const SingleSection = () => (
  <div style={{ background: 'var(--black)', padding: '18px 22px' }}>
    <PortalNav items={[{ label: 'Report Branding', current: true }]} />
  </div>
);

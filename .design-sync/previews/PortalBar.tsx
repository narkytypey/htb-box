import * as React from 'react';
import { PortalBar, PortalNav } from '@donerup/ui';

export const Dashboard = () => (
  <PortalBar>
    <PortalNav
      items={[
        { label: 'Store Ops' },
        { label: 'Reports', href: '/admin/report-template' },
        { label: 'Branding', href: '/admin/branding' },
        { label: 'Directory', current: true },
      ]}
    />
  </PortalBar>
);

export const ToolScreen = () => (
  <PortalBar>
    <PortalNav items={[{ label: 'Store Report Builder', current: true }]} />
  </PortalBar>
);

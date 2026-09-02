import * as React from 'react';
import { FieldHelp } from '@donerup/ui';

export const LogoSpec = () => (
  <div style={{ maxWidth: 420 }}>
    <FieldHelp>
      Paste a direct link to the asset. PNG or SVG, 320×80 or larger,
      transparent background preferred. The file is fetched once and checked
      before it is used as report letterhead.
    </FieldHelp>
  </div>
);

export const ForbiddenExplainer = () => (
  <div style={{ maxWidth: 420 }}>
    <FieldHelp>
      This page is not available from a staff workstation. If you need a report
      template changed, raise it with the IT Service Desk.
    </FieldHelp>
  </div>
);

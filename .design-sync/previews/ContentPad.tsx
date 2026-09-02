import * as React from 'react';
import { ContentPad, PanelTitle, FieldHelp } from '@donerup/ui';

export const ForbiddenScreen = () => (
  <ContentPad>
    <PanelTitle>Forbidden: internal use only</PanelTitle>
    <FieldHelp>
      This page is not available from a staff workstation. If you need a report
      template changed, raise it with the IT Service Desk.
    </FieldHelp>
  </ContentPad>
);

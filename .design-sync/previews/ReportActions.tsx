import * as React from 'react';
import { ReportActions, Button, ReportTextarea, PanelTitle } from '@donerup/ui';

export const InForm = () => (
  <div>
    <PanelTitle>Report template</PanelTitle>
    <ReportTextarea placeholder="Paste or edit the store report template…" />
    <ReportActions>
      <Button variant="secondary">Render report</Button>
    </ReportActions>
  </div>
);

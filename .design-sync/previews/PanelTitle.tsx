import * as React from 'react';
import { PanelTitle } from '@donerup/ui';

export const Sections = () => (
  <div>
    <PanelTitle>Store operations — week 34</PanelTitle>
    <PanelTitle>Sites reporting</PanelTitle>
    <PanelTitle>Recent reports</PanelTitle>
    <PanelTitle>Custom report logo</PanelTitle>
  </div>
);

export const Single = () => <PanelTitle>Report template</PanelTitle>;

import * as React from 'react';
import { Card, Field, Button } from '@donerup/ui';

export const SignIn = () => (
  <Card title="Sign in" subtitle="Donerup Restaurant Group — Employee Directory">
    <Field id="username" label="Username" />
    <Field id="password" label="Password" type="password" />
    <Button>Sign in</Button>
  </Card>
);

export const TitleOnly = () => (
  <Card title="Access request">
    <Field id="site" label="Site code" placeholder="DNR-001" />
    <Button>Submit</Button>
  </Card>
);

export const Bare = () => (
  <Card>
    <p style={{ margin: 0, fontSize: 14, lineHeight: 1.6 }}>
      A card with no heading — the surface on its own, showing the 2px black
      border and the hard 5px orange shadow.
    </p>
  </Card>
);

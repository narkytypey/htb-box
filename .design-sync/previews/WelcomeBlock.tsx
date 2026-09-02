import * as React from 'react';
import { WelcomeBlock } from '@donerup/ui';

export const SignedIn = () => <WelcomeBlock tag="Signed in">Welcome, jdoe</WelcomeBlock>;

export const WithoutTag = () => <WelcomeBlock>Store operations</WelcomeBlock>;

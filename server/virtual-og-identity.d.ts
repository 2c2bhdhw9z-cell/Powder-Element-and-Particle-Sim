declare module "virtual:og-identity" {
  export const ogIdentity: {
    site: {
      title?: string;
      description?: string;
      type?: string;
      card?: string;
      image?: string;
      banner?: string;
      color?: string;
    };
  };
}

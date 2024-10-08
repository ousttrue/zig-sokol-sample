export type LinkType = {
  name: string,
  url: string,
};
export type ItemType = {
  name: string,
  links: LinkType[],
};
export type ItemGroupType = {
  name: string,
  url?: string,
  items: ItemType[],
};

export const GROUPS: ItemGroupType[] = [
  {
    name: 'basic',
    items: [
      {
        name: 'clear',
        links: [],
      },
    ],
  },
];
